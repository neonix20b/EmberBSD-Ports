#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; strict C11/C++17 alloca link regression with target fixtures.
set -eu
[ "$#" -eq 4 ] || {
    echo 'Usage: mesa-alloca.sh PATCHED_MESA CROSS_PREFIX SYSROOT NEW_WORK' >&2
    exit 2
}
source_dir=$(CDPATH= cd -- "$1" && pwd -P)
prefix=$2 sysroot=$3 work=$4
tests=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
[ ! -e "$work" ] && [ ! -L "$work" ]
mkdir -p "$work/baseline/include"
cp "$source_dir/include/c99_alloca.h" "$work/baseline/include/"
patch -f -R -F0 -p0 -d "$work/baseline" \
    < "$tests/../patches/mesa/patch-include_c99__alloca.h" > "$work/reverse.log"
for language in c11 cpp17; do
    case "$language" in
        c11) compiler=$prefix/bin/aarch64--netbsd-gcc; set -- -std=c11 -x c ;;
        cpp17)
            compiler=$prefix/bin/aarch64--netbsd-g++
            set -- -std=c++17 -x c++ \
                -isystem "$sysroot/usr/pkg/gcc16/include/c++" \
                -isystem "$sysroot/usr/pkg/gcc16/include/c++/aarch64--netbsd"
            ;;
    esac
    for variant in baseline patched; do
        case "$variant" in
            baseline) include=$work/baseline/include;;
            patched) include=$source_dir/include;;
        esac
        status=0
        "$compiler" --sysroot="$sysroot" \
            -B"$sysroot/usr/pkg/gcc16/lib/gcc/aarch64--netbsd/16.2.0/" "$@" \
            -O2 -fno-builtin -Wall -Wextra -Werror -I"$include" \
            "$tests/mesa-alloca.c" -o "$work/$variant-$language" \
            -L"$sysroot/usr/pkg/gcc16/lib" -Wl,-rpath,/usr/pkg/gcc16/lib \
            > "$work/$variant-$language.log" 2>&1 || status=$?
        if [ "$variant" = baseline ]; then
            [ "$status" -ne 0 ]
            grep -q "undefined reference to .*alloca" "$work/$variant-$language.log"
        else
            [ "$status" -eq 0 ]
            "$prefix/bin/aarch64--netbsd-nm" -u "$work/$variant-$language" \
                > "$work/$variant-$language.undefined"
            if grep -w alloca "$work/$variant-$language.undefined"; then exit 1; fi
        fi
    done
done
echo 'PASS: original strict C11/C++17 links fail; compiler builtin links without libc alloca'
echo "Run patched-c11 and patched-cpp17 on the target, with zero and several arguments: $work"
