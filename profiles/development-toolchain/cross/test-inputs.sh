#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; verify failures before a long cross-compiler build starts.
set -eu
[ "$#" -eq 4 ] || { echo 'Usage: test-inputs.sh EXPORTED_PKGSRC GCC_ARCHIVE SYSROOT TOOLDIR' >&2; exit 2; }
tree=$1 archive=$2 sysroot=$3 tools=$4
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/gcc16-cross-inputs.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
reject() {
    name=$1 expected=$2; shift 2
    if sh "$here/build.sh" "$@" "$work/$name-output" > "$work/$name.log" 2>&1; then
        echo "Accepted invalid input: $name" >&2; exit 1
    fi
    grep -F "$expected" "$work/$name.log" >/dev/null
    test ! -e "$work/$name-output"
}
printf corrupt > "$work/archive.tar.xz"
reject archive 'GCC archive SHA256 mismatch' "$tree" "$work/archive.tar.xz" "$sysroot" "$tools"
mkdir -p "$work/tree/lang/gcc16"
cp "$tree/lang/gcc16/distinfo" "$work/tree/lang/gcc16/"
cp -R "$tree/lang/gcc16/patches" "$work/tree/lang/gcc16/"
printf '\ncorrupt\n' >> "$work/tree/lang/gcc16/patches/patch-gcc_cp_module.cc"
reject patch 'Patch SHA1 mismatch: patch-gcc_cp_module.cc' "$work/tree" "$archive" "$sysroot" "$tools"
rm "$work/tree/lang/gcc16/patches/patch-gcc_cp_module.cc"
reject missing 'Missing patch: patch-gcc_cp_module.cc' "$work/tree" "$archive" "$sysroot" "$tools"
CROSS_JOBS=0 reject jobs 'CROSS_JOBS must be positive' "$tree" "$archive" "$sysroot" "$tools"
CROSS_JOBS=00 reject zeroes 'CROSS_JOBS must be positive' "$tree" "$work/archive.tar.xz" "$sysroot" "$tools"
echo 'PASS: corrupt archive, corrupt/missing repair and invalid jobs fail before extraction'
