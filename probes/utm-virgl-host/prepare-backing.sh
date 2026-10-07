#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted selected-file UTM overlay projection.
set -eu
[ "$#" -eq 3 ] || { echo "Usage: $0 ORIGINAL_RENDERER_ARCHIVE PINNED_RAW_INPUT_DIR NEW_ABSOLUTE_WORK" >&2; exit 2; }
archive=$1 inputs=$2 work=$3
case "$work" in /*) ;; *) echo 'Work path must be absolute' >&2; exit 2 ;; esac
[ ! -e "$work" ] || { echo 'Work path must be new' >&2; exit 2; }
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
hash() { shasum -a 256 "$1" | awk '{print $1}'; }
[ "$(hash "$archive")" = 6834f45a0b6e904bc8836426657ffcbf13cbc2c2632fb63e6eec57e23670055f ]
while IFS="$(printf '\t')" read -r file rev url sum; do
 case "$file" in ''|'#'*) continue ;; esac
 [ -f "$inputs/$file" ] && [ "$(hash "$inputs/$file")" = "$sum" ] || { echo "Pinned raw input mismatch: $file" >&2; exit 1; }
done < "$recipe/create-sources.tsv"
for pair in '123e0bc-upstream.patch a1c804a65190f5d11caa150748e80655f9f98617a7b5711e1529d522cd32e68e' 'create-qemu-local.patch a1a8bc72138759435fe4f99f96463bf1cf229a0e3f54edbde64767e4037bdcd7' 'create-renderer-local.patch 3f131d11dd3d5e570c5f57df4d3bb4611e053b2a5cea75ea06e9f6c908e93ef1' 'backing-qemu-local.patch d5e6a264f3902843f0225723aaa6cdface622bdd1c5516338a08a38e2c2d72de'; do
 set -- $pair; [ "$(hash "$recipe/patches/$1")" = "$2" ] || { echo "Patch mismatch: $1" >&2; exit 1; }
done
mkdir -p "$work/qemu/original/hw/display" "$work/qemu/original/include/hw/virtio" "$work/sections" "$work/renderer"
for stem in virtio-gpu-gl virtio-gpu-virgl virtio-gpu; do cp "$inputs/utm-qemu-6601422-$stem.c" "$work/qemu/original/hw/display/$stem.c"; done
cp "$inputs/utm-qemu-6601422-virtio-gpu.h" "$work/qemu/original/include/hw/virtio/virtio-gpu.h"
cp "$inputs/utm-v5.0.6-qemu.patch" "$work/original-overlay.mbox"
awk -v dir="$work/sections" -v manifest="$work/overlay-manifest.tsv" -v inventory="$work/overlay-inventory.tsv" -f "$recipe/tests/project-overlay.awk" "$work/original-overlay.mbox"
cat > "$work/expected-inventory.tsv" <<'EOF'
1 2870e745b902e83ef413ebde08e4c77c7dfead7f hw/display/virtio-gpu-gl.c
2 2870e745b902e83ef413ebde08e4c77c7dfead7f hw/display/virtio-gpu-virgl.c
3 2870e745b902e83ef413ebde08e4c77c7dfead7f include/hw/virtio/virtio-gpu.h
4 3824e0d9968ae9cc4f7809f385615541ed176120 hw/display/virtio-gpu-virgl.c
5 3824e0d9968ae9cc4f7809f385615541ed176120 include/hw/virtio/virtio-gpu.h
6 3bdba2ae2ed1158b9fc9822562d86b8e287d8490 hw/display/virtio-gpu-virgl.c
7 3bdba2ae2ed1158b9fc9822562d86b8e287d8490 hw/display/virtio-gpu.c
8 3bdba2ae2ed1158b9fc9822562d86b8e287d8490 include/hw/virtio/virtio-gpu.h
EOF
cmp "$work/expected-inventory.tsv" "$work/overlay-inventory.tsv"
apply() {
 patch -f -F 0 -d "$1" -p1 < "$2" > "$3" 2>&1 || { cat "$3" >&2; exit 1; }
 if grep -Ei 'fuzz|offset|FAILED|Reversed|previously applied|Skipping|malformed' "$3"; then echo 'Non-exact application' >&2; exit 1; fi
}
cp -R "$work/qemu/original" "$work/qemu/post-overlay"
for section in "$work"/sections/*.patch; do apply "$work/qemu/post-overlay" "$section" "$section.log"; done
while read -r path sum; do [ "$(hash "$work/qemu/post-overlay/$path")" = "$sum" ]; done <<'EOF'
hw/display/virtio-gpu-gl.c 36ae5b2763e48aa696a574ac7c50c46e59020cfa47989d1c2d0deb000ad174f4
hw/display/virtio-gpu-virgl.c fa586e30890ca8e55899b69151bcba043acb89b1deddd2b89f8c27d4fb81c1e0
hw/display/virtio-gpu.c 669effd30d221024f40af56b842247a5a2be8c68bc471ac533415214ac48d304
include/hw/virtio/virtio-gpu.h 25e032f22e32d860fea74c1e598de1df0268111a1d2e7367dcbdd9e5f42a8a73
EOF
# Only hunk coordinates change. The complete old hunk must match uniquely.
awk -f "$recipe/tests/rebase-create.awk" "$work/qemu/post-overlay/hw/display/virtio-gpu-virgl.c" "$recipe/patches/create-qemu-local.patch" > "$work/create-qemu-overlay.patch"
sed '/^@@ /d' "$work/create-qemu-overlay.patch" > "$work/create-derived-body"
sed '/^@@ /d' "$recipe/patches/create-qemu-local.patch" > "$work/create-accepted-body"
cmp "$work/create-derived-body" "$work/create-accepted-body"
cp -R "$work/qemu/post-overlay" "$work/qemu/baseline"
apply "$work/qemu/baseline" "$work/create-qemu-overlay.patch" "$work/create-qemu-overlay.log"
[ "$(hash "$work/qemu/baseline/hw/display/virtio-gpu-virgl.c")" = c381fd9bdf0c6fb3e58dcb01c263b1cc77d510f0b39fa31e654933c7de1f5544 ]
mkdir -p "$work/qemu/raw-create/hw/display"
cp "$work/qemu/original/hw/display/virtio-gpu-virgl.c" "$work/qemu/raw-create/hw/display/virtio-gpu-virgl.c"
apply "$work/qemu/raw-create" "$recipe/patches/create-qemu-local.patch" "$work/create-qemu-raw.log"
[ "$(hash "$work/qemu/raw-create/hw/display/virtio-gpu-virgl.c")" = 4eb8fc1fc00dc8a159de537a4c9d11e6cc4f2b9c444f7cf4bf235d06b0a3f330 ]
for name in virgl_create_resource_error virgl_cmd_create_resource_2d virgl_cmd_create_resource_3d; do
 awk -v name="$name" -f "$recipe/tests/extract-create.awk" "$work/qemu/raw-create/hw/display/virtio-gpu-virgl.c" > "$work/$name-raw.inc"
 awk -v name="$name" -f "$recipe/tests/extract-create.awk" "$work/qemu/baseline/hw/display/virtio-gpu-virgl.c" > "$work/$name-overlay.inc"
 cmp "$work/$name-raw.inc" "$work/$name-overlay.inc"
done
cp -R "$work/qemu/baseline" "$work/qemu/patched"
apply "$work/qemu/patched" "$recipe/patches/backing-qemu-local.patch" "$work/backing-qemu.log"
[ "$(hash "$work/qemu/patched/hw/display/virtio-gpu-virgl.c")" = a7bb36d50c0ff30a88a2313554fbf3c73a3f9bf24298a10035ac6351ecf26e5f ]
# Selected renderer inputs, not a duplicated full dependency checkout.
prefix=utmapp-virglrenderer-5d26f60
for file in src/virglrenderer.c src/virgl_resource.c src/virgl_resource.h src/virgl_protocol.h src/vrend/vrend_renderer.c src/vrend/vrend_renderer.h src/vrend/iov.c src/vrend/vrend_iov.h src/gallium/auxiliary/util/u_inlines.h; do
 tar -xzf "$archive" -C "$work/renderer" --strip-components=1 "$prefix/$file"
done
sed -e 's/virgl_get_iovec_size/vrend_get_iovec_size/g' -e 's/@@ -9167,16 +9167,16/@@ -9376,16 +9376,16/' -e 's/@@ -9190,16 +9190,19/@@ -9399,16 +9399,19/' "$recipe/patches/123e0bc-upstream.patch" > "$work/123e0bc-utm.patch"
[ "$(hash "$work/123e0bc-utm.patch")" = 8ea940b70f7ee4563ed4dc36e5d835a3ec9347fdcf65523bb9e891659906b1d7 ]
apply "$work/renderer" "$work/123e0bc-utm.patch" "$work/iov.log"
[ "$(hash "$work/renderer/src/vrend/vrend_renderer.c")" = 34d99a5726459112444cab327e1ed7849fc732e7e3a5704dbfa641dc05747c87 ]
apply "$work/renderer" "$recipe/patches/create-renderer-local.patch" "$work/create-renderer.log"
[ "$(hash "$work/renderer/src/vrend/vrend_renderer.c")" = 7bb55e69e483df96d7e14895dab2e0cae6f13d60c8fcd0293169a2942fe421df ]
find "$work/qemu" "$work/renderer" -type f ! -name '*.orig' ! -name '*.rej' -exec shasum -a 256 {} \; > "$work/prepared-sha256.txt"
printf '%s\n' 'PASS: exact eight-section selected-file overlay projection, accepted CREATE body identity, backing patch; no full QEMU build.'
