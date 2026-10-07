#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# AI-assisted failure contracts for original source preparation.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: test-prepare.sh ARCHIVE_CACHE NEW_WORK' >&2; exit 2; }
cache=$1
work=$2
case "$cache:$work" in /*:/*) ;; *) exit 2 ;; esac
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$work"
mkdir "$work/cache" "$work/existing"
printf '%s\n' preserved > "$work/existing/sentinel"
if sh "$here/prepare.sh" otbr "$work/existing" "$cache" > "$work/existing.log" 2>&1; then
    echo 'Existing work directory was accepted.' >&2; exit 1
fi
[ "$(cat "$work/existing/sentinel")" = preserved ]
[ "$(find "$work/existing" -type f | wc -l | tr -d ' ')" = 1 ]
echo 'PASS: existing work is preserved'
while read -r archive expected url destination; do
    case "$archive" in ''|'#'*) continue ;; esac
    ln -s "$cache/$archive" "$work/cache/$archive"
done < "$here/sources/otbr.tsv"
# Break the LAST nested archive: earlier valid archives must not be extracted.
last=$(awk '!/^#/ && NF {name=$1} END {print name}' "$here/sources/otbr.tsv")
rm "$work/cache/$last"
printf '%s\n' corrupt > "$work/cache/$last"
if sh "$here/prepare.sh" otbr "$work/rejected" "$work/cache" > "$work/checksum.log" 2>&1; then
    echo 'Corrupted nested archive was accepted.' >&2; exit 1
fi
grep -F "Checksum mismatch: $last; nothing extracted." "$work/checksum.log"
[ "$(find "$work/rejected/source" -mindepth 1 | wc -l | tr -d ' ')" = 0 ]
echo 'PASS: every archive is verified before any extraction'
