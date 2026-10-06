#!/bin/sh
# Verify every original source before extracting any component.
set -eu
umask 077
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh prepare-sources.sh NEW_WORK [ARCHIVE_DIRECTORY]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple work path.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
mkdir "$work"
mkdir "$work/archives" "$work/src" "$work/build" "$work/logs" "$work/tools" "$work/install"
while read -r component archive expected url; do
    if [ "$#" = 2 ]; then
        cp "$2/$archive" "$work/archives/$archive"
    else
        curl -fLsS --connect-timeout 20 --max-time 900 "$url" -o "$work/archives/$archive"
    fi
    actual=$(sha256 -q "$work/archives/$archive")
    [ "$actual" = "$expected" ] || { echo "Checksum mismatch: $archive" >&2; exit 2; }
    printf '%s %s %s\n' "$archive" "$actual" "$url" >> "$work/logs/sources.txt"
done < "$recipe/sources.tsv"
while read -r component archive expected url; do
    tar -xf "$work/archives/$archive" -C "$work/src"
done < "$recipe/sources.tsv"
cp "$recipe/sources.tsv" "$work/sources.tsv"
printf 'Verified sources: %s/src\n' "$work"
