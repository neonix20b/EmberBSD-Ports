#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: source-guards.sh ABS_NEW_TEST_ROOT' >&2; exit 2; }
root=$1
case "$root" in /*) ;; *) echo 'Use an absolute path.' >&2; exit 2 ;; esac
case "$root" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple path.' >&2; exit 2 ;; esac
[ ! -e "$root" ] && [ ! -L "$root" ] || { echo 'Test root already exists.' >&2; exit 2; }
recipe=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
mkdir "$root"
mkdir "$root/cache"
printf 'deliberately corrupt source archive\n' > "$root/cache/gnuradio-3.10.12.0.tar.gz"
status=0
"$recipe/build.sh" "$root/work" "$root/cache" > "$root/hash-rejection.log" 2>&1 || status=$?
[ "$status" = 2 ] || { cat "$root/hash-rejection.log" >&2; exit 1; }
grep -Fx 'Checksum mismatch: gnuradio-3.10.12.0.tar.gz' "$root/hash-rejection.log" >/dev/null
[ -d "$root/work/src" ] && [ -z "$(ls -A "$root/work/src")" ] || {
    echo 'Bad archive reached extraction.' >&2; exit 1;
}
printf 'keep\n' > "$root/work/preserve.txt"
status=0
"$recipe/build.sh" "$root/work" "$root/cache" > "$root/work-rejection.log" 2>&1 || status=$?
[ "$status" = 2 ] && [ "$(cat "$root/work/preserve.txt")" = keep ] || exit 1
grep -Fx 'Work path already exists.' "$root/work-rejection.log" >/dev/null
echo 'Corrupt archive rejected before extraction; existing work preserved: PASS'
