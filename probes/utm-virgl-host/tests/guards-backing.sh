#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted strict backing preparation/extraction guards.
set -eu
[ "$#" -eq 3 ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive=$1 inputs=$2 work=$3
case "$work" in /*) ;; *) exit 2 ;; esac
[ ! -e "$work" ];mkdir "$work"
reject() { name=$1;shift;if "$@" > "$work/$name.log" 2>&1;then echo "Unexpected accepted guard: $name" >&2;exit 1;fi;printf 'PASS: rejected %s\n' "$name"; }
reject relative sh "$recipe/prepare-backing.sh" "$archive" "$inputs" relative
reject existing sh "$recipe/prepare-backing.sh" "$archive" "$inputs" "$work"
printf 'invalid archive\n' > "$work/bad.tar.gz"
reject archive sh "$recipe/prepare-backing.sh" "$work/bad.tar.gz" "$inputs" "$work/archive-output"
mkdir "$work/inputs";cp "$inputs"/utm-qemu-6601422-virtio-gpu*.c "$inputs/utm-qemu-6601422-virtio-gpu.h" "$inputs/utm-v5.0.6-qemu.patch" "$work/inputs/"
printf '\ncorrupt\n' >> "$work/inputs/utm-qemu-6601422-virtio-gpu.c"
reject raw sh "$recipe/prepare-backing.sh" "$archive" "$work/inputs" "$work/raw-output"
cp "$inputs/utm-qemu-6601422-virtio-gpu.c" "$work/inputs/utm-qemu-6601422-virtio-gpu.c"
rm "$work/inputs/utm-qemu-6601422-virtio-gpu.h"
reject missing sh "$recipe/prepare-backing.sh" "$archive" "$work/inputs" "$work/missing-output"
cp -R "$recipe" "$work/recipe"
printf '\ncorrupt\n' >> "$work/recipe/patches/backing-qemu-local.patch"
reject patch sh "$work/recipe/prepare-backing.sh" "$archive" "$inputs" "$work/patch-output"
reject absent awk -v name=missing_function -f "$recipe/tests/extract-create.awk" "$inputs/utm-qemu-6601422-virtio-gpu-virgl.c"
cat "$inputs/utm-qemu-6601422-virtio-gpu-virgl.c" "$inputs/utm-qemu-6601422-virtio-gpu-virgl.c" > "$work/duplicate.c"
reject duplicate awk -v name=virgl_resource_attach_backing -f "$recipe/tests/extract-create.awk" "$work/duplicate.c"
sed -n '677,690p' "$inputs/utm-qemu-6601422-virtio-gpu-virgl.c" > "$work/truncated.c"
reject truncated awk -v name=virgl_resource_attach_backing -f "$recipe/tests/extract-create.awk" "$work/truncated.c"
reject missing-shape awk -v kind=struct -v name=missing -f "$recipe/tests/extract-backing-shape.awk" "$inputs/utm-qemu-6601422-virtio-gpu-virgl.c"
mkdir "$work/sections"
sed 's|diff --git a/hw/display/virtio-gpu-gl.c b/hw/display/virtio-gpu-gl.c|diff --git a/hw/display/virtio-gpu-gl.c b/hw/display/renamed.c|' "$inputs/utm-v5.0.6-qemu.patch" > "$work/renamed.mbox"
reject rename awk -v dir="$work/sections" -v manifest="$work/manifest" -v inventory="$work/inventory" -f "$recipe/tests/project-overlay.awk" "$work/renamed.mbox"
sed '/^diff --git a\/hw\/display\/virtio-gpu-gl.c /a\
GIT binary patch\
' "$inputs/utm-v5.0.6-qemu.patch" > "$work/binary.mbox"
reject binary awk -v dir="$work/sections" -v manifest="$work/manifest" -v inventory="$work/inventory" -f "$recipe/tests/project-overlay.awk" "$work/binary.mbox"
# Whole old C8b hunk must match exactly and uniquely before changing positions.
printf 'no real QEMU context\n' > "$work/non-context.c"
reject context awk -f "$recipe/tests/rebase-create.awk" "$work/non-context.c" "$recipe/patches/create-qemu-local.patch"
printf '%s\n' 'PASS: backing guards; no compile, fetch, installation or dependency changes.'
