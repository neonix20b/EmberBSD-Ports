#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || exit 2
builder=$1
tmp=$(mktemp -d /tmp/ember-foundation-guards.XXXXXX)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir "$tmp/existing" "$tmp/archives"
printf '%s\n' preserved > "$tmp/existing/sentinel"
rc=0
sh "$builder" "$tmp/existing" > "$tmp/existing.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ]
grep -q 'File exists' "$tmp/existing.log"
[ "$(cat "$tmp/existing/sentinel")" = preserved ]
: > "$tmp/archives/opencv-5.0.0.tar.gz"
rc=0
sh "$builder" "$tmp/bad" "$tmp/archives" > "$tmp/hash.log" 2>&1 || rc=$?
[ "$rc" -eq 2 ]
grep -q 'Checksum mismatch: opencv-5.0.0.tar.gz' "$tmp/hash.log"
[ -z "$(ls -A "$tmp/bad/src")" ]
rc=0
JOBS=00 sh "$builder" "$tmp/zero-jobs" > "$tmp/jobs.log" 2>&1 || rc=$?
[ "$rc" -eq 2 ]
[ ! -d "$tmp/zero-jobs" ]
echo 'PASS: existing work, corrupted archive before extraction and zero jobs rejected'
