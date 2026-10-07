#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted bounded reported CREATE failure source stage.
set -eu
[ "$#" -eq 3 ] || { echo "Usage: $0 ORIGINAL_RENDERER_ARCHIVE PINNED_RAW_INPUT_DIR NEW_ABSOLUTE_WORK" >&2; exit 2; }
archive=$1
inputs=$2
work=$3
case "$work" in /*) ;; *) echo 'Work path must be absolute' >&2; exit 2 ;; esac
[ ! -e "$work" ] || { echo 'Work path must be new' >&2; exit 2; }
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
hash() { if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1"; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
# Verify every raw input before creating a work tree. No implicit downloads.
while IFS="$(printf '\t')" read -r file revision url expected; do
    case "$file" in ''|'#'*) continue ;; esac
    [ -f "$inputs/$file" ] && [ "$(hash "$inputs/$file")" = "$expected" ] || {
        echo "Pinned input SHA256 mismatch or missing: $file" >&2; exit 1;
    }
done < "$recipe/create-sources.tsv"
[ "$(hash "$recipe/patches/create-qemu-local.patch")" = a1a8bc72138759435fe4f99f96463bf1cf229a0e3f54edbde64767e4037bdcd7 ] || { echo 'Local QEMU CREATE patch SHA256 mismatch' >&2; exit 1; }
[ "$(hash "$recipe/patches/create-renderer-local.patch")" = 3f131d11dd3d5e570c5f57df4d3bb4611e053b2a5cea75ea06e9f6c908e93ef1 ] || { echo 'Local renderer CREATE patch SHA256 mismatch' >&2; exit 1; }
mkdir "$work"
# Audit all sequential relevant overlay hunks against actual CREATE ranges,
# adjusting ranges for preceding changes between patches. This does not apply
# the overlay, qualify its context/offsets, or build complete QEMU.
for name in virgl_cmd_create_resource_2d virgl_cmd_create_resource_3d; do
    awk -v name="$name" -v rangefile="$work/$name.range" -f "$recipe/tests/extract-create.awk" "$inputs/utm-qemu-6601422-virtio-gpu-virgl.c" > "$work/$name-original.inc"
done
cat "$work/virgl_cmd_create_resource_2d.range" "$work/virgl_cmd_create_resource_3d.range" > "$work/create-ranges.txt"
awk -f "$recipe/tests/overlay-create.awk" "$work/create-ranges.txt" "$inputs/utm-v5.0.6-qemu.patch" > "$work/overlay-create-audit.log"
# The reviewed IOV entry and its output hash contract are deliberately unchanged.
sh "$recipe/prepare.sh" "$archive" "$work/renderer"
cp -R "$work/renderer/patched" "$work/renderer/create-patched"
mkdir -p "$work/qemu/original/hw/display" "$work/qemu/original/include/hw/virtio"
for stem in virtio-gpu-virgl virtio-gpu virtio-gpu-base virtio-gpu-gl; do
    cp "$inputs/utm-qemu-6601422-$stem.c" "$work/qemu/original/hw/display/$stem.c"
done
cp "$inputs/utm-qemu-6601422-virtio-gpu.h" "$work/qemu/original/include/hw/virtio/virtio-gpu.h"
cp "$inputs/utm-v5.0.6-qemu.patch" "$work/qemu/utm-original-overlay.patch"
cp -R "$work/qemu/original" "$work/qemu/patched"
for component in qemu renderer; do
    if [ "$component" = qemu ]; then target=$work/qemu/patched; else target=$work/renderer/create-patched; fi
    patch -f -N -F 0 -d "$target" -p1 < "$recipe/patches/create-$component-local.patch" > "$work/create-$component-patch.log" 2>&1
    if grep -E 'fuzz|offset|FAILED|Reversed' "$work/create-$component-patch.log"; then
        echo 'Unexpected CREATE patch application' >&2; exit 1
    fi
done
[ "$(hash "$work/qemu/patched/hw/display/virtio-gpu-virgl.c")" = 4eb8fc1fc00dc8a159de537a4c9d11e6cc4f2b9c444f7cf4bf235d06b0a3f330 ]
[ "$(hash "$work/renderer/create-patched/src/vrend/vrend_renderer.c")" = 7bb55e69e483df96d7e14895dab2e0cae6f13d60c8fcd0293169a2942fe421df ]
printf '%s\n' 'Prepared pinned reported CREATE failure patches after accepted IOV backport; no complete QEMU/host build.'
