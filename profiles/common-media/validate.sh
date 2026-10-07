#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Validate source metadata before creating a pkgsrc export.
set -eu
profile=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
pkg=$profile/recipes/multimedia/ffmpeg9
expected='multimedia/ffmpeg9 ffmpeg-9.0.2.tar.xz 8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz'
actual=$(awk '!/^#/ && NF { if (NF != 4) exit 1; print $1, $2, $3, $4 }' "$profile/sources.tsv")
[ "$actual" = "$expected" ] || { echo 'Incorrect common media source pin.' >&2; exit 2; }
for file in Makefile Makefile.common DESCR ALTERNATIVES PLIST distinfo options.mk buildlink3.mk; do
    [ -f "$pkg/$file" ] || { echo "Incomplete FFmpeg recipe: $file" >&2; exit 2; }
done
required=$(awk '/^SHA1 \(patch-/ {gsub(/[()]/,"",$2); print $2}' "$pkg/distinfo")
[ "$(printf '%s\n' "$required" | wc -l | tr -d ' ')" = 17 ] || {
    echo 'Incomplete FFmpeg patch manifest.' >&2; exit 2;
}
[ "$(find "$pkg/patches" -type f -name 'patch-*' | wc -l | tr -d ' ')" = 17 ] || {
    echo 'FFmpeg patch inventory differs.' >&2; exit 2;
}
for name in $required; do
    expected=$(awk -v n="($name)" '$1=="SHA1" && $2==n {print $4}' "$pkg/distinfo")
    actual=$(sed '/[$]NetBSD.*/d' "$pkg/patches/$name" | shasum -a 1 | awk '{print $1}')
    [ "$actual" = "$expected" ] || { echo "FFmpeg patch checksum differs: $name" >&2; exit 2; }
done
