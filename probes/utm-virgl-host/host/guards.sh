#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted negative preparation and receipt checks; no GPU needed.
set -eu
[ "$#" -eq 6 ] || { echo "Usage: $0 RENDERER EPOXY MESA RAW_INPUTS BUILT_WORK NEW_ABSOLUTE_GUARD_WORK" >&2; exit 2; }
renderer=$1 epoxy=$2 mesa=$3 inputs=$4 built=$5 out=$6
case "$out" in /*) ;; *) exit 2;; esac
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$out"
count=0
reject() {
    name=$1 pattern=$2; shift 2
    if "$@" > "$out/$name.log" 2>&1; then echo "Unexpected success: $name" >&2; exit 1; fi
    grep -q "$pattern" "$out/$name.log" || { cat "$out/$name.log" >&2; exit 1; }
    count=$((count + 1))
}
reject relative 'Work path must be absolute' sh "$recipe/prepare.sh" "$renderer" "$epoxy" "$mesa" "$inputs" relative
reject missing 'SHA256 mismatch' sh "$recipe/prepare.sh" "$out/absent" "$epoxy" "$mesa" "$inputs" "$out/missing-work"
printf 'not an archive\n' > "$out/bad-archive"
reject archive 'SHA256 mismatch' sh "$recipe/prepare.sh" "$out/bad-archive" "$epoxy" "$mesa" "$inputs" "$out/archive-work"
reject existing 'File exists' sh "$recipe/prepare.sh" "$renderer" "$epoxy" "$mesa" "$inputs" "$out"
cp -R "$recipe" "$out/recipe"
printf '\n' >> "$out/recipe/libepoxy-current-angle.patch"
reject patch 'SHA256 mismatch' sh "$out/recipe/prepare.sh" "$renderer" "$epoxy" "$mesa" "$inputs" "$out/patch-work"
cp "$recipe/libepoxy-current-angle.patch" "$out/recipe/libepoxy-current-angle.patch"
printf '\n' >> "$out/recipe/decoder-truncated-error.patch"
reject decoder-patch 'SHA256 mismatch' sh "$out/recipe/prepare.sh" "$renderer" "$epoxy" "$mesa" "$inputs" "$out/decoder-patch-work"
cp "$recipe/decoder-truncated-error.patch" "$out/recipe/decoder-truncated-error.patch"
printf '\n' >> "$out/recipe/context-errors.patch"
reject context-patch 'SHA256 mismatch' sh "$out/recipe/prepare.sh" "$renderer" "$epoxy" "$mesa" "$inputs" "$out/context-patch-work"
cp "$recipe/context-errors.patch" "$out/recipe/context-errors.patch"
printf '\n' >> "$out/recipe/epoxy-files.tsv"
reject manifest 'SHA256 mismatch' sh "$out/recipe/prepare.sh" "$renderer" "$epoxy" "$mesa" "$inputs" "$out/manifest-work"
# Private copies receive mutations; original sources and libraries are untouched.
mkdir "$out/native" "$out/native/renderer-build"
ln -s "$built/renderer" "$out/native/renderer"
ln -s "$built/khronos" "$out/native/khronos"
cp -R "$built/epoxy" "$out/native/epoxy"
cp -R "$built/prefix" "$out/native/prefix"
cp "$built/renderer-build/config.h" "$out/native/renderer-build/config.h"
cp "$built/source-sha256.txt" "$built/installed-sha256.txt" "$built/binaries-sha256.txt" "$out/native/"
printf '\n' >> "$out/native/epoxy/include/epoxy/gl.h"
reject source 'computed checksum did NOT match' sh "$recipe/test-native.sh" "$out/native" "$out/no-frameworks"
grep -q 'epoxy/include/epoxy/gl.h: FAILED' "$out/native/native-source-check.log"
cp "$built/epoxy/include/epoxy/gl.h" "$out/native/epoxy/include/epoxy/gl.h"
printf '\n' >> "$out/native/prefix/include/virgl/virglrenderer.h"
reject header 'computed checksum did NOT match' sh "$recipe/test-native.sh" "$out/native" "$out/no-frameworks"
grep -q 'prefix/include/virgl/virglrenderer.h: FAILED' "$out/native/native-install-check.log"
cp "$built/prefix/include/virgl/virglrenderer.h" "$out/native/prefix/include/virgl/virglrenderer.h"
printf '\n' >> "$out/native/prefix/lib/libvirglrenderer.1.dylib"
reject library 'computed checksum did NOT match' sh "$recipe/test-native.sh" "$out/native" "$out/no-frameworks"
grep -q 'prefix/lib/libvirglrenderer.1.dylib: FAILED' "$out/native/native-install-check.log"
printf 'PASS: %s host guards; originals and installed host unchanged.\n' "$count"
