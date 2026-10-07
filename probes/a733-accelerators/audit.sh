#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 EmberBSD contributors
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 MESA_SOURCE ORANGEPI_LINUX_SOURCE OUTPUT_DIRECTORY" >&2
    exit 2
fi
mesa=$(cd "$1" && pwd)
bsp=$(cd "$2" && pwd)
umask 077
mkdir "$3"
out=$(cd "$3" && pwd)
probe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

hash_file()
{
    if command -v sha256 >/dev/null 2>&1; then
        sha256 -q "$1"
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

while IFS="$(printf '\t')" read -r owner path expected; do
    case "$owner" in
        \#*|'') continue ;;
        mesa) root=$mesa ;;
        bsp) root=$bsp ;;
        *) echo "Unknown source owner: $owner" >&2; exit 1 ;;
    esac
    actual=$(hash_file "$root/$path")
    if [ "$actual" != "$expected" ]; then
        echo "Source checksum mismatch: $owner/$path" >&2
        exit 1
    fi
done < "$probe/sources.tsv"

sed -n "s/^[[:space:]]*'\([^']*\/gc_feature_database\.h\)',\{0,1\}[[:space:]]*$/\1/p" \
    "$mesa/src/etnaviv/hwdb/meson.build" | LC_ALL=C sort > "$out/mesa-inputs"
awk '$1 == "mesa" && $2 ~ /\/gc_feature_database\.h$/ {
    sub(/^src\/etnaviv\/hwdb\//, "", $2); print $2
}' "$probe/sources.tsv" | LC_ALL=C sort > "$out/audit-inputs"
if [ ! -s "$out/mesa-inputs" ] || ! cmp -s "$out/mesa-inputs" "$out/audit-inputs"; then
    echo 'Mesa hardware database inputs differ from the pinned audit.' >&2
    exit 1
fi

cc=${CC:-cc}
"$cc" -std=c99 -Wall -Wextra -Werror -DA733_VIP_DB \
    -I "$bsp/bsp/drivers/npu/aw_nna_vip/vip2/inc" \
    "$probe/feature-db.c" -o "$out/vendor-features"
"$out/vendor-features"
while IFS= read -r input; do
    db=${input%/gc_feature_database.h}
    "$cc" -std=c99 -Wall -Wextra -Werror \
        -I "$mesa/src/etnaviv/hwdb/$db" \
        "$probe/feature-db.c" -o "$out/mesa-$db-features"
    printf '%s: ' "$db"
    "$out/mesa-$db-features"
done < "$out/mesa-inputs"
echo 'PASS: pinned source audit only; no hardware, DMA or inference tested.'
