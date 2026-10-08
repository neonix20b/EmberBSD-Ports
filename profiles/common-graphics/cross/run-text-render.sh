#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), guarded installed text/image consumer.
set -eu
[ "$#" = 2 ] || { echo 'Usage: run-text-render.sh BUNDLE NEW_LOGS' >&2; exit 2; }
bundle=$(CDPATH= cd -- "$1" && pwd -P)
sh "$bundle/run-mesa-package-tests.sh" --verify-sysroot "$bundle" /
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ]
for setting in LD_LIBRARY_PATH LD_PRELOAD FONTCONFIG_FILE FONTCONFIG_PATH \
    PANGOCAIRO_BACKEND PANGO_LANGUAGE GIO_MODULE_DIR GI_TYPELIB_PATH FREETYPE_PROPERTIES; do
    eval "value=\${$setting-}"
    [ -z "$value" ] || { echo "Unexpected caller override: $setting" >&2; exit 2; }
done
mkdir "$2"
logs=$(CDPATH= cd -- "$2" && pwd -P)
mkdir "$logs/cache"
timeout=${TIMEOUT:-/usr/bin/timeout}
case "$timeout" in /*) ;; *) exit 2;; esac
[ -x "$timeout" ]
uname -a > "$logs/platform.log"
ldd "$bundle/bin/text-render" > "$logs/ldd.log" 2>&1
awk '$2 == "=>" && $3 !~ /^\// {bad=1} END {exit bad}' "$logs/ldd.log"
for control in no-draw no-ligature; do
    control_result=0
    env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/pkg/bin HOME="$logs" \
        XDG_CACHE_HOME="$logs/cache" FONTCONFIG_FILE="$bundle/fixtures/fonts.conf" \
        "$timeout" -k 5 30 "$bundle/bin/control-$control" \
        "$bundle/fixtures/DejaVuSans.ttf" "$logs/control-$control.png" \
        > "$logs/control-$control.log" 2>&1 || control_result=$?
    case "$control" in
        no-draw) reason='text changes the white image';;
        no-ligature) reason='real ffi ligature on/off shaping';;
    esac
    if [ "$control_result" != 1 ] || ! grep -Fqx "FAIL cycle 1: $reason" "$logs/control-$control.log"; then
        cat "$logs/control-$control.log"
        echo "Negative control did not reach its oracle: $control (exit $control_result)" >&2
        exit 1
    fi
    echo "PASS: negative control $control reached its expected oracle"
done
result=0
env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/pkg/bin HOME="$logs" \
    XDG_CACHE_HOME="$logs/cache" FONTCONFIG_FILE="$bundle/fixtures/fonts.conf" \
    "$timeout" -k 5 60 "$bundle/bin/text-render" \
    "$bundle/fixtures/DejaVuSans.ttf" "$logs/text.png" \
    > "$logs/text-render.log" 2>&1 || result=$?
cat "$logs/text-render.log"
if [ "$result" = 0 ]; then
    while IFS= read -r provider; do
        case "$provider" in
            /usr/pkg/*)
                awk -v p="$provider" '$2 == p {found=1} END {exit !found}' \
                    "$bundle/runtime-libraries.sha256" || {
                    echo "Unrecorded live package provider: $provider" >&2; result=1;
                };;
            /usr/lib/*|/lib/*|/libexec/ld.elf_so|/usr/libexec/ld.elf_so) ;;
            *) echo "Foreign live provider: $provider" >&2; result=1;;
        esac
    done <<EOF
$(sed -n 's/^LOADED: //p' "$logs/text-render.log" | awk '!seen[$0]++')
EOF
    for name in libpango-1.0 libpangocairo-1.0 libpangoft2-1.0 libglib-2.0 libgobject-2.0 \
        libpcre2-8 libharfbuzz libfreetype libfontconfig libcairo libpixman-1 libpng16 libfribidi; do
        awk -v p="/usr/pkg/lib/$name.so" '$1 == "LOADED:" && index($2, p) == 1 {found=1} END {exit !found}' \
            "$logs/text-render.log" || {
            echo "Missing live provider: $name" >&2; result=1;
        }
    done
    awk '/^PASS cycle [1-4]:/ {cycles++; seen[$3]++}
        /^PASS: four installed text shaping\/rasterization\/PNG lifecycles$/ {complete++}
        END {exit !(cycles == 4 && complete == 1 && seen["1:"] == 1 &&
            seen["2:"] == 1 && seen["3:"] == 1 && seen["4:"] == 1)}' \
        "$logs/text-render.log" || result=1
    sh "$bundle/run-mesa-package-tests.sh" --verify-sysroot "$bundle" / || result=1
    [ "$result" != 0 ] || echo 'PASS: all live text/image package providers are recorded'
fi
printf '%s\n' "$result" > "$logs/exit-status"
exit "$result"
