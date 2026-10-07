#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: source-guards.sh ABS_NEW_TEST_ROOT' >&2; exit 2; }
root=$1
case "$root" in /*) ;; *) exit 2 ;; esac
case "$root" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
[ ! -e "$root" ] && [ ! -L "$root" ] || { echo 'Test root already exists.' >&2; exit 2; }
recipe=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
read -r archive expected url < "$recipe/sources.tsv"
mkdir "$root"
mkdir "$root/cache"
printf 'deliberately corrupt archive\n' > "$root/cache/$archive"
result=0
"$recipe/build.sh" "$root/work" "$root/cache" > "$root/hash-rejection.log" 2>&1 || result=$?
[ "$result" = 2 ] || { cat "$root/hash-rejection.log" >&2; exit 1; }
grep -Fx "Checksum mismatch: $archive" "$root/hash-rejection.log" >/dev/null
[ -d "$root/work/src" ] && [ -z "$(ls -A "$root/work/src")" ] || exit 1
printf 'preserve\n' > "$root/work/marker.txt"
result=0
"$recipe/build.sh" "$root/work" "$root/cache" > "$root/work-rejection.log" 2>&1 || result=$?
[ "$result" = 2 ] && [ "$(cat "$root/work/marker.txt")" = preserve ] || exit 1
grep -Fx 'Work path already exists.' "$root/work-rejection.log" >/dev/null
echo 'Corrupt source rejected before extraction; existing work retained: PASS'
