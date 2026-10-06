#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
set -eu
[ "$#" = 3 ] || { echo 'Usage: check-theme-icons.sh TOOL SOURCE NEW_OUTPUT' >&2; exit 2; }
tool=$1
source=$2/themes/zenburn/titlebar
output=$3
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
mkdir "$output"
count=0
while read -r mode input name expected; do
    if [ -f "$output/$input" ]; then
        input=$output/$input
    else
        input=$source/$input
    fi
    actual=$("$tool" "$mode" "$input" "$output/$name")
    [ "$actual" = "$expected" ] || { echo "Icon RGBA mismatch: $name" >&2; exit 1; }
    count=$((count + 1))
done < "$recipe/theme-icons.tsv"
[ "$count" = 13 ]
if "$tool" unsupported "$source/close_focus.png" "$output/rejected.png"; then
    echo 'Unsupported converter operation accepted.' >&2
    exit 1
fi
printf 'PASS: all %s derived icons match upstream ImageMagick RGBA values\n' "$count"
