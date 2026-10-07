#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 2 ] || { echo 'Usage: fetch-model.sh tinyllama OUTPUT.task' >&2; exit 2; }
case "$1" in tinyllama) ;; *) echo 'Unknown model.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
model=$1
output=$2
checksum()
{
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1"
    else shasum -a 256 "$1" | cut -d ' ' -f 1; fi
}
while read -r name hash url; do
    [ "$name" = "$model" ] || continue
    if [ ! -f "$output" ]; then
        curl -fL --retry 3 "$url" -o "$output.part"
        [ "$(checksum "$output.part")" = "$hash" ] || { echo 'Model checksum mismatch.' >&2; exit 1; }
        mv "$output.part" "$output"
    fi
    [ "$(checksum "$output")" = "$hash" ] || { echo 'Cached model checksum mismatch.' >&2; exit 1; }
    printf '%s %s\n' "$name" "$hash"
    exit 0
done < "$recipe/models.tsv"
echo 'Model manifest entry is missing.' >&2
exit 1
