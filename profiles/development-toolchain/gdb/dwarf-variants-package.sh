#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), prepare DWP-only and zstd test inputs.
set -eu
[ "$#" = 2 ] || { echo "Usage: $0 LLVM_DWP FIXTURES" >&2; exit 2; }
dwp=$1 fixtures=$2
objcopy=${OBJCOPY:-/usr/pkg/bin/gobjcopy}
readelf=${READELF:-/usr/pkg/bin/greadelf}
fixtures=$(CDPATH= cd -- "$fixtures" && pwd)
"$dwp" --version > "$fixtures/dwp-version.txt"
cd "$fixtures"
for version in 4 5; do
    for width in 32 64; do
        name=dwp-v$version-w$width
        [ ! -e "$name/program.dwp" ]
        "$dwp" "$name/main.dwo" "$name/helper.dwo" -o "$name/program.dwp"
        "$readelf" --wide --section-headers "$name/program.dwp" > "$name/sections.txt"
        grep -q '\.debug_cu_index' "$name/sections.txt"
        "$readelf" --debug-dump=cu_index "$name/program.dwp" > "$name/index.txt"
        grep -q 'Number of used entries: *2' "$name/index.txt"
        # These are generated fixtures only. Removing all DWO copies makes
        # a successful lookup depend on the indexed package, not fallback.
        rm "$name/main.dwo" "$name/helper.dwo"
        printf '%s/program\tc\n' "$name" >> cases.tsv
    done
done
for width in 32 64; do
    name=compressed-w$width-zstd
    "$objcopy" --compress-debug-sections=zstd "c-v5-w$width-o2" "$name"
    "$readelf" --wide --section-headers "$name" > "$name.sections.txt"
    grep '\.debug_info' "$name.sections.txt" | grep -q ' C '
    printf '%s\tc\n' "$name" >> cases.tsv
done
