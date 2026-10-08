#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), actual upstream and wscons contract execution.
set -eu
[ "$#" = 2 ] || { echo 'Usage: run-drm-dependency-tests.sh BUNDLE NEW_LOGS' >&2; exit 2; }
bundle=$(CDPATH= cd -- "$1" && pwd -P)
sh "$bundle/run-mesa-package-tests.sh" --verify-sysroot "$bundle" /
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ]
for setting in LD_LIBRARY_PATH LD_PRELOAD; do
    eval "value=\${$setting-}"
    [ -z "$value" ] || { echo "Unexpected loader override: $setting" >&2; exit 2; }
done
mkdir "$2"
logs=$(CDPATH= cd -- "$2" && pwd -P)
timeout=${TIMEOUT:-/usr/bin/timeout}
case "$timeout" in /*) ;; *) exit 2;; esac
[ -x "$timeout" ]
uname -a > "$logs/platform.log"
# Check each real test executable once. Mock libdrm is linked into the liftoff
# test executable only; its library under test remains the installed package.
for executable in "$bundle"/bin/*; do
    case "$executable" in *.sh) continue;; esac
    ldd "$executable" > "$logs/$(basename "$executable").ldd" 2>&1
    awk '$2 == "=>" && $3 !~ /^\// {bad=1} END {exit bad}' "$logs/$(basename "$executable").ldd"
    while read -r loaded_path; do
        case "$loaded_path" in
            /usr/pkg/*)
                awk -v p="$loaded_path" '$2 == p {found=1} END {exit !found}' "$bundle/runtime-libraries.sha256" || {
                    echo "Unrecorded package dependency: $loaded_path" >&2; exit 1;
                };;
            /lib/*|/usr/lib/*|/libexec/ld.elf_so|/usr/libexec/ld.elf_so) ;;
            *) echo "Unexpected library: $loaded_path" >&2; exit 1;;
        esac
    done <<EOF
$(awk '$2 == "=>" {print $3}' "$logs/$(basename "$executable").ldd")
EOF
done
failed=0
count=0
while IFS="$(printf '\t')" read -r name kind program argument; do
    case "$name" in ''|*[!A-Za-z0-9_@.+-]*) exit 2;; esac
    case "$program" in bin/*) ;; *) exit 2;; esac
    case "$program$argument" in *..*) exit 2;; esac
    case "$kind" in
        elf)
            set -- "$bundle/$program"
            [ "$argument" = - ] || set -- "$@" "$argument";;
        edid)
            case "$argument" in data/edid/*.edid) ;; *) exit 2;; esac
            set -- /bin/sh "$bundle/$program" "$bundle/$argument";;
        *) exit 2;;
    esac
    status=0
    env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/pkg/bin \
        DI_EDID_DECODE="$bundle/bin/di-edid-decode" DI_EDID_PRINT="$bundle/bin/di-edid-print" \
        "$timeout" -k 5 60 "$@" > "$logs/$name.log" 2>&1 || status=$?
    printf '%s\t%s\n' "$name" "$status" | tee -a "$logs/results.tsv"
    count=$((count + 1))
    if [ "$status" != 0 ]; then
        failed=$((failed + 1))
        cat "$logs/$name.log"
        case "$status" in 124|137) break;; esac
    fi
done < "$bundle/checks.tsv"
printf 'Executed %s invocations; failures=%s (remaining entries after a timeout were not run)\n' "$count" "$failed"
[ "$failed" = 0 ]
