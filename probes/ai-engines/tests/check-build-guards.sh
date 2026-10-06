#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || exit 2
build=$1
recipe=$(CDPATH= cd "$(dirname "$build")" && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ember-ai-guards.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir "$tmp/existing" "$tmp/cache"
printf 'preserve\n' > "$tmp/existing/sentinel"
if sh "$build" "$tmp/existing" "$tmp/cache" > "$tmp/existing.log" 2>&1; then
    echo 'Existing work tree accepted.' >&2; exit 1
fi
[ "$(cat "$tmp/existing/sentinel")" = preserve ]
if JOBS=0 sh "$build" "$tmp/zero-jobs" "$tmp/cache" > "$tmp/jobs.log" 2>&1; then
    echo 'Zero parallelism accepted.' >&2; exit 1
fi
grep -q 'JOBS must be positive' "$tmp/jobs.log"
[ ! -e "$tmp/zero-jobs" ]
cat "$recipe/sources.tsv" "$recipe/dependencies.tsv" | while read -r name hash url; do
    printf 'corrupt\n' > "$tmp/cache/$name"
done
if sh "$build" "$tmp/bad-source" "$tmp/cache" > "$tmp/source.log" 2>&1; then
    echo 'Corrupt source archive accepted.' >&2; exit 1
fi
grep -q 'Checksum mismatch' "$tmp/source.log"
for item in "$tmp/bad-source/src"/*; do
    [ ! -e "$item" ] || { echo 'Extracted source before all hashes passed.' >&2; exit 1; }
done
[ ! -d "$tmp/bad-source/install" ]
printf 'PASS build guards: existing tree, zero jobs, corrupt archive before extraction\n'
