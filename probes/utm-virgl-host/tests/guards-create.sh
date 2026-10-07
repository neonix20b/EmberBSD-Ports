#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted bounded CREATE preparation rejection contracts.
set -eu
export LC_ALL=C
[ "$#" -eq 3 ] || { echo "Usage: $0 ORIGINAL_ARCHIVE PINNED_RAW_INPUT_DIR NEW_ABSOLUTE_WORK" >&2; exit 2; }
archive=$1
inputs=$2
work=$3
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$work" in /*) ;; *) exit 2 ;; esac
mkdir "$work"
reject() {
    label=$1;message=$2;shift 2
    if "$@" > "$work/$label.log" 2>&1; then result=0; else result=$?; fi
    printf '%s\n' "$result" > "$work/$label.status"
    [ "$result" -ne 0 ];grep -Fq "$message" "$work/$label.log"
    printf 'PASS: %s rejected (status %s)\n' "$label" "$result"
}
for script in "$recipe/prepare-create.sh" "$recipe/test-create.sh" "$recipe/tests/guards-create.sh"; do sh -n "$script"; done
reject relative 'Work path must be absolute' sh "$recipe/prepare-create.sh" "$archive" "$inputs" relative-work
mkdir "$work/existing";printf '%s\n' 'preserve me' > "$work/existing/sentinel"
reject existing 'Work path must be new' sh "$recipe/prepare-create.sh" "$archive" "$inputs" "$work/existing"
grep -Fqx 'preserve me' "$work/existing/sentinel"
printf '%s\n' 'not the pinned archive' > "$work/wrong.tar.gz"
reject archive 'Original archive SHA256 mismatch' sh "$recipe/prepare-create.sh" "$work/wrong.tar.gz" "$inputs" "$work/wrong-archive"
[ ! -e "$work/wrong-archive/renderer" ]
mkdir "$work/inputs"
while IFS="$(printf '\t')" read -r file revision url expected; do
 case "$file" in ''|'#'*) continue ;; esac
 cp "$inputs/$file" "$work/inputs/$file"
 printf '\n%s\n' 'corrupt' >> "$work/inputs/$file"
 reject "corrupt-$file" 'Pinned input SHA256 mismatch or missing' sh "$recipe/prepare-create.sh" "$archive" "$work/inputs" "$work/corrupt-source"
 [ ! -e "$work/corrupt-source" ]
 cp "$inputs/$file" "$work/inputs/$file"
done < "$recipe/create-sources.tsv"
rm "$work/inputs/utm-qemu-6601422-virtio-gpu.h"
reject missing 'Pinned input SHA256 mismatch or missing' sh "$recipe/prepare-create.sh" "$archive" "$work/inputs" "$work/missing-source"
for component in qemu renderer; do
 cp -R "$recipe" "$work/recipe-$component"
 printf '\n%s\n' 'corrupt' >> "$work/recipe-$component/patches/create-$component-local.patch"
 if [ "$component" = qemu ]; then message='Local QEMU CREATE patch SHA256 mismatch'; else message='Local renderer CREATE patch SHA256 mismatch'; fi
 reject "$component-patch" "$message" sh "$work/recipe-$component/prepare-create.sh" "$archive" "$inputs" "$work/wrong-$component-patch"
done
# Exact production function extraction rejects absence, duplication and loss of
# the closing body. The compiled RED gates use originals, not these negatives.
for name in virgl_cmd_create_resource_2d virgl_cmd_create_resource_3d; do
 src=$inputs/utm-qemu-6601422-virtio-gpu-virgl.c
 awk -v name="$name" -f "$recipe/tests/extract-create.awk" "$src" > "$work/$name.c"
 cat "$work/$name.c" "$work/$name.c" > "$work/$name-duplicate.c"
 sed '$d' "$work/$name.c" > "$work/$name-truncated.c"
 for kind in absent duplicate truncated; do
  if [ "$kind" = absent ]; then source=/dev/null; else source=$work/$name-$kind.c; fi
  reject "$name-$kind" 'Unexpected CREATE extraction shape' awk -v name="$name" -f "$recipe/tests/extract-create.awk" "$source"
 done
done
# Renderer extraction negative guards use the original archive already verified
# by prepare.sh; no second compiler or unchanged IOV tests are needed.
sh "$recipe/prepare-create.sh" "$archive" "$inputs" "$work/good" > "$work/good.log"
for name in vrend_renderer_resource_create vrend_renderer_resource_destroy; do
 src=$work/good/renderer/create-patched/src/vrend/vrend_renderer.c
 awk -v name="$name" -f "$recipe/tests/extract-create.awk" "$src" > "$work/$name.c"
 cat "$work/$name.c" "$work/$name.c" > "$work/$name-duplicate.c"
 sed '$d' "$work/$name.c" > "$work/$name-truncated.c"
 for kind in absent duplicate truncated; do
  if [ "$kind" = absent ]; then source=/dev/null; else source=$work/$name-$kind.c; fi
  reject "$name-$kind" 'Unexpected CREATE extraction shape' awk -v name="$name" -f "$recipe/tests/extract-create.awk" "$source"
 done
done
# Directly challenge overlap detection independent of pinned-input rejection.
printf '%s\n' 'diff --git a/hw/display/virtio-gpu-virgl.c b/hw/display/virtio-gpu-virgl.c' '@@ -290,1 +290,1 @@' '- old' '+ new' > "$work/overlap.patch"
reject overlap 'Overlay hunk overlaps CREATE' awk -f "$recipe/tests/overlay-create.awk" "$work/good/create-ranges.txt" "$work/overlap.patch"
printf '%s\n' 'PASS: syntax, source/patch hashes, paths, extraction and complete-overlay CREATE guards.'
