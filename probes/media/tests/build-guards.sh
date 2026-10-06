#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
recipe=$1
scratch=$(mktemp -d "${TMPDIR:-/tmp}/ember-media-guards.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
mkdir "$scratch/existing" "$scratch/archives"
if JOBS=0 sh "$recipe/build.sh" "$scratch/zero" > "$scratch/zero.log" 2>&1; then
    echo 'Zero parallelism was accepted.' >&2; exit 1
fi
[ ! -e "$scratch/zero" ]
grep 'JOBS must be positive' "$scratch/zero.log" >/dev/null
if sh "$recipe/build.sh" "$scratch/existing" > "$scratch/existing.log" 2>&1; then
    echo 'Existing work directory was accepted.' >&2; exit 1
fi
printf 'not an archive\n' > "$scratch/archives/ffmpeg-9.0.2.tar.xz"
if sh "$recipe/build.sh" "$scratch/corrupt" "$scratch/archives" > "$scratch/corrupt.log" 2>&1; then
    echo 'Corrupt source was accepted.' >&2; exit 1
fi
grep 'Checksum mismatch: ffmpeg-9.0.2.tar.xz' "$scratch/corrupt.log" >/dev/null
[ "$(find "$scratch/corrupt/src" -type f | wc -l | tr -d ' ')" = 0 ]
echo 'PASS media build guards: zero parallelism, existing work, checksum before extraction.'
