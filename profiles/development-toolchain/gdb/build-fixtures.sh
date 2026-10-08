#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), compile live-debugging DWO contracts.
set -eu
[ "$#" = 3 ] || { echo "Usage: $0 GCC16_DRIVER SYSROOT NEW_WORK" >&2; exit 2; }
gcc=$1 sysroot=$2 work=$3
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$work"
cp "$here/runtime.c" "$work/"
work=$(CDPATH= cd -- "$work" && pwd)
"$gcc" --sysroot="$sysroot" -std=c11 -Wall -Wextra -Werror \
    -c "$here/abi-layout.c" -o "$work/abi-layout.o"
for width in 32 64; do
    (cd "$work"; "$gcc" --sysroot="$sysroot" -O0 -gdwarf-5 -gdwarf$width \
        -gsplit-dwarf -fno-omit-frame-pointer runtime.c -o runtime-$width)
done
echo 'Built DWARF32/64 live-debugging fixtures.'
