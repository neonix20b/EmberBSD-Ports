#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
set -eu
[ "$#" -eq 3 ] || { echo "Usage: $0 CONSUMER_EXECUTABLE FFMPEG_EXECUTABLE NEW_WORK" >&2; exit 2; }
consumer=$1
ffmpeg=$2
mkdir "$3"
work=$(CDPATH= cd -- "$3" && pwd)
"$ffmpeg" -version > "$work/ffmpeg-version.txt"
grep -q '^ffmpeg version 9.0.2 ' "$work/ffmpeg-version.txt"
"$ffmpeg" -hide_banner -nostdin -f lavfi -i color=c=red:size=64x48:rate=5 \
    -t 1 -c:v ffv1 -metadata title='Ember FFmpeg 9' "$work/sample.mkv" \
    > "$work/encode.log" 2>&1
printf 'invalid media\n' > "$work/invalid.mkv"
"$consumer" "$work/sample.mkv" "$work/invalid.mkv" > "$work/consumer.log" 2>&1 || {
    cat "$work/consumer.log" >&2; exit 1;
}
cat "$work/consumer.log"
