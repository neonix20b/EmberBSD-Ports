#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), canonical DWP patch/checksum regression.
set -eu
[ "$#" = 2 ] || { echo "Usage: $0 VERIFIED_LLVM_ARCHIVE NEW_WORK" >&2; exit 2; }
archive=$1 work=$2
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
recipe=$root/profiles/common-build-tools/recipes/lang/llvm
patch=$recipe/patches/patch-lib_DWP_DWP.cpp
mkdir "$work"
work=$(CDPATH= cd -- "$work" && pwd)
[ "$(shasum -a 256 "$archive" | awk '{print $1}')" = \
    c98bbef08a2b4c2613cd50e9aa9ae7b69b1fe6c16b2c40373bc0ab6116fdf78a ]
expected=$(awk '/^SHA1 \(patch-lib_DWP_DWP.cpp\)/ { print $4 }' "$recipe/distinfo")
actual=$(sed '/[$]NetBSD.*/d' "$patch" | shasum -a 1 | awk '{print $1}')
[ "$expected" = "$actual" ]
tar -xf "$archive" -C "$work" llvm-project-23.1.2.src/llvm/lib/DWP/DWP.cpp
tree=$work/llvm-project-23.1.2.src/llvm
cp "$tree/lib/DWP/DWP.cpp" "$work/DWP.cpp.orig"
patch -f -N -F 0 -p0 -d "$tree" < "$patch" > "$work/forward.log"
if patch -f -N -F 0 -p0 -d "$tree" < "$patch" > "$work/repeated.log" 2>&1; then
    echo 'FAIL: repeated DWP patch accepted' >&2
    exit 1
fi
[ ! -e "$root/profiles/development-toolchain/gdb/dwarf-variants-llvm-dwp.patch" ]
[ ! -e "$root/profiles/development-toolchain/gdb/dwarf-variants-dwp-build.sh" ]
grep -q '^PKGREVISION=.*1$' "$recipe/Makefile"
echo 'PASS: pinned source, patch hash, zero-fuzz application, repeated rejection and single recipe ownership'
