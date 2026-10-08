#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted isolated no-device full-UMD execution guard.
set -eu
sha_file() {
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1";
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
verify_bundle() {
# Validate every bundle file before executing either the binary or ldd.
[ -f "$bundle/artifacts.sha256" ] && [ ! -L "$bundle/artifacts.sha256" ]
while read -r expected relative; do
    case "$relative" in /*|*..*|'') echo 'Invalid bundle receipt path' >&2; exit 1;; esac
    [ -f "$bundle/$relative" ] && [ ! -L "$bundle/$relative" ]
    [ "$(sha_file "$bundle/$relative")" = "$expected" ] || { echo "Bundle drift: $relative" >&2; exit 1; }
done < "$bundle/artifacts.sha256"
[ "$(find "$bundle" -type f | wc -l | tr -d ' ')" -eq "$(($(wc -l < "$bundle/artifacts.sha256") + 1))" ]
[ -z "$(find "$bundle" -type l -print)" ] || { echo 'Unexpected bundle symlink' >&2; exit 1; }
while read -r expected absolute; do
    case "$absolute" in /usr/pkg/gcc16/lib/libstdc++.so.*|/usr/pkg/gcc16/lib/libgcc_s.so.*) ;; *) exit 1;; esac
    [ "$(sha_file "$runtime_root$absolute")" = "$expected" ] || { echo "Runtime drift: $absolute" >&2; exit 1; }
done < "$bundle/runtime.sha256"
[ "$(wc -l < "$bundle/runtime.sha256")" -eq 2 ]
echo 'PASS: complete bundle and common GCC16 runtime hashes'
}
if [ "${1-}" = --verify-sysroot ]; then
    [ "$#" = 3 ] || exit 2
    bundle=$(CDPATH= cd -- "$2" && pwd -P)
    runtime_root=$(CDPATH= cd -- "$3" && pwd -P)
    verify_bundle
    exit 0
fi
[ "$#" = 2 ] || { echo 'Usage: run-no-device.sh BUNDLE NEW_LOGS' >&2; exit 2; }
bundle=$(CDPATH= cd -- "$1" && pwd -P)
case "$bundle" in *' '*|*'	'*) echo 'Whitespace paths unsupported' >&2; exit 2;; esac
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ]
for setting in LD_LIBRARY_PATH LD_PRELOAD LD_LIBRARY_PATH_64 LD_PRELOAD_64; do
    eval "value=\${$setting-}"
    [ -z "$value" ] || { echo "Unexpected loader override: $setting" >&2; exit 2; }
done
runtime_root=
verify_bundle
[ ! -e /dev/aipu ] && [ ! -L /dev/aipu ] || { echo '/dev/aipu must be absent' >&2; exit 1; }
mkdir "$2"
logs=$(CDPATH= cd -- "$2" && pwd -P)
uname -a > "$logs/platform.log"
ldd "$bundle/bin/compass-no-device" > "$logs/ldd-consumer.log" 2>&1
ldd "$bundle/lib/libaipudrv.so.6.1.1" > "$logs/ldd-umd.log" 2>&1
status=0
env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin /usr/bin/timeout -k 5 60 \
    "$bundle/bin/compass-no-device" "$bundle/lib/libaipudrv.so.6.1.1" \
    > "$logs/no-device.log" 2>&1 || status=$?
cat "$logs/no-device.log"
if [ "$status" -eq 0 ]; then
    while IFS= read -r library; do
        case "$library" in
            "$bundle/lib/libaipudrv.so.6.1.1"|/usr/lib/*|/lib/*|/usr/libexec/ld.elf_so|/libexec/ld.elf_so) ;;
            /usr/pkg/gcc16/lib/*)
                awk -v p="$library" '$2 == p {found=1} END {exit !found}' "$bundle/runtime.sha256" || status=1;;
            *) echo "Foreign loaded provider: $library" >&2; status=1;;
        esac
    done <<EOF
$(sed -n 's/^LOADED: //p' "$logs/no-device.log" | sort -u)
EOF
    grep -q '^PASS: full UMD no-device API,' "$logs/no-device.log" || status=1
fi
printf '%s\n' "$status" > "$logs/exit-status"
exit "$status"
