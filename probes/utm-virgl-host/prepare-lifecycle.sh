#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted exact downstream lifecycle source stage.
set -eu
[ "$#" -eq 3 ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
archive=$1
inputs=$2
work=$3
hash() { shasum -a 256 "$1" | awk '{print $1}'; }
# Accepted preparer validates original archive, all raw inputs, full selected
# overlay inventory, CREATE identity and C8c1 output before this delta.
sh "$recipe/prepare-backing.sh" "$archive" "$inputs" "$work"
[ "$(hash "$recipe/lifecycle-sources.tsv")" = 79c1280553e988d0c41733284d4366857f14fe569ca383efabd947f5055e3bc1 ] || { echo 'Lifecycle manifest mismatch' >&2;exit 1; }
mkdir -p "$work/renderer-extra-original"
while IFS="$(printf '\t')" read -r kind path sum;do
 case "$kind" in ''|'#'*) continue;; original)
  tar -xzf "$archive" -C "$work/renderer-extra-original" --strip-components=1 "utmapp-virglrenderer-5d26f60/$path"
  [ "$(hash "$work/renderer-extra-original/$path")" = "$sum" ] || { echo "Original mismatch: $path" >&2;exit 1; };;
 input) [ "$(hash "$work/$path")" = "$sum" ] || { echo "C8c1 input mismatch: $path" >&2;exit 1; };;
 patch) [ "$(hash "$recipe/$path")" = "$sum" ] || { echo "Delta mismatch: $path" >&2;exit 1; };;
 output) :;;
 *) echo "Unexpected manifest class: $kind" >&2;exit 1;;
 esac
done < "$recipe/lifecycle-sources.tsv"
cp "$inputs/utm-qemu-6601422-virtio-gpu-base.c" "$work/qemu/patched/hw/display/virtio-gpu-base.c"
cp -R "$work/qemu/patched" "$work/qemu/lifecycle"
cp -R "$work/renderer" "$work/renderer-lifecycle"
for path in src/virglrenderer.h src/vrend/vrend_winsys.c;do
 cp "$work/renderer-extra-original/$path" "$work/renderer-lifecycle/$path"
done
apply() {
 ruby "$recipe/tests/lifecycle-seams.rb" verify-patch "$1" "$2"
 patch -f -F 0 -d "$1" -p1 < "$2" > "$3" 2>&1 || { cat "$3" >&2;exit 1; }
 if grep -Ei 'fuzz|offset|FAILED|Reversed|previously applied|Skipping|malformed' "$3";then echo 'Non-exact lifecycle application' >&2;exit 1;fi
}
apply "$work/qemu/lifecycle" "$recipe/patches/lifecycle-qemu-local.patch" "$work/lifecycle-qemu.log"
apply "$work/renderer-lifecycle" "$recipe/patches/lifecycle-renderer-local.patch" "$work/lifecycle-renderer.log"
while IFS="$(printf '\t')" read -r kind path sum;do
 [ "$kind" = output ] || continue
 [ "$(hash "$work/$path")" = "$sum" ] || { echo "Lifecycle output mismatch: $path" >&2;exit 1; }
done < "$recipe/lifecycle-sources.tsv"
find "$work/qemu/lifecycle" "$work/renderer-lifecycle" "$work/renderer-extra-original" -type f ! -name '*.orig' ! -name '*.rej' -exec shasum -a 256 {} \; > "$work/lifecycle-prepared-sha256.txt"
printf '%s\n' 'PASS: lifecycle exact delta after accepted full selected overlay+C8b+C8c1; source contract only.'
