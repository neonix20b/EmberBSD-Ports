#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), DWARF entry-value regression inputs.
set -eu
[ "$#" = 3 ] || { echo "Usage: $0 GCC16_DRIVER SYSROOT NEW_WORK" >&2; exit 2; }
cc=$1 sysroot=$2 work=$3
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$work"
"$cc" --version > "$work/compiler.txt"
for width in 32 64; do
    define=
    [ "$width" != 64 ] || define=-DDW64
    "$cc" --sysroot="$sysroot" -B"$sysroot/usr/pkg/gcc16/lib/gcc/aarch64--netbsd/16.2.0/" \
        $define "$here/dwarf-entry-value.S" -o "$work/entry-w$width"
done
