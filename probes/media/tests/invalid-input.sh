#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
consumer=$1
video=$2
work=$3
# The trusted complete fixture size is independent of the damaged copies.
size=$(wc -c < "$video" | tr -d ' ')
"$consumer" --read "$video" "$size"
dd if=/dev/zero of="$work/invalid.media" bs=1 count="$size" 2>/dev/null
dd if="$video" of="$work/truncated.mkv" bs=1 count="$((size / 2))" 2>/dev/null
dd if="$video" of="$work/tail-one.mkv" bs=1 count="$((size - 1))" 2>/dev/null
dd if="$video" of="$work/tail-sixty-four.mkv" bs=1 count="$((size - 64))" 2>/dev/null
for bad in "$work/invalid.media" "$work/truncated.mkv" "$work/missing.media" \
    "$work/tail-one.mkv" "$work/tail-sixty-four.mkv"; do
    status=0
    "$consumer" --read "$bad" "$size" > "$work/reject.log" 2>&1 || status=$?
    [ "$status" = 1 ] || { cat "$work/reject.log" >&2; echo "Unexpected rejection status: $status" >&2; exit 1; }
    grep 'FAIL FFmpeg:' "$work/reject.log" >/dev/null
    if grep 'PASS FFmpeg' "$work/reject.log" >/dev/null; then
        echo 'Invalid media was accepted.' >&2; exit 1
    fi
done
# Exercise the diagnostic guard independently of the trusted-length guard.
status=0
"$consumer" --read "$work/tail-one.mkv" "$((size - 1))" > "$work/reject.log" 2>&1 || status=$?
[ "$status" = 1 ]
grep 'FAIL FFmpeg: clean decoder/container diagnostics' "$work/reject.log" >/dev/null
echo 'PASS FFmpeg rejects missing, same-size malformed, midstream and tail-truncated fixtures.'
