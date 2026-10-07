#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: fetch.sh ARCHIVE_DIRECTORY' >&2; exit 2; }
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
archive=$(CDPATH= cd "$1" && pwd)
checksum()
{
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1"
    else shasum -a 256 "$1" | cut -d ' ' -f 1; fi
}
for manifest in "$recipe/sources.tsv" "$recipe/dependencies.tsv"; do
    while read -r name hash url; do
        file=$archive/$name.tar.gz
        if [ ! -f "$file" ]; then
            curl -fL --retry 3 "$url" -o "$file.part"
            [ "$(checksum "$file.part")" = "$hash" ] || {
                echo "Checksum mismatch: $name" >&2; exit 1;
            }
            mv "$file.part" "$file"
        fi
        [ "$(checksum "$file")" = "$hash" ] || {
            echo "Checksum mismatch: $name (remove corrupt archive before retrying)" >&2; exit 1;
        }
        printf '%s %s\n' "$name" "$hash"
    done < "$manifest"
done
