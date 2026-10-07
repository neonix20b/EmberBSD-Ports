#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: sh tests/build-guards.sh ABS_NEW_GUARD_WORK' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir "$work"
mkdir "$work/existing" "$work/cache"
echo preserve > "$work/existing/marker"
if sh "$here/build.sh" "$work/existing" "$work/cache" > "$work/existing.log" 2>&1; then
    echo 'Existing work path was accepted.' >&2; exit 1
fi
grep -q 'Work path already exists' "$work/existing.log"
[ "$(cat "$work/existing/marker")" = preserve ]
# The first manifest input is deliberately corrupted. It must fail before extraction.
archive=$(awk 'NR == 1 {print $2}' "$here/sources.tsv")
printf 'deliberately corrupt source archive\n' > "$work/cache/$archive"
if sh "$here/build.sh" "$work/rejected" "$work/cache" > "$work/corrupt.log" 2>&1; then
    echo 'Corrupt source archive was accepted.' >&2; exit 1
fi
grep -q 'Source checksum mismatch' "$work/corrupt.log"
[ -d "$work/rejected/src" ]
[ -z "$(ls -A "$work/rejected/src")" ]
echo 'PASS existing-work rejection and corrupt archive rejected before extraction'
