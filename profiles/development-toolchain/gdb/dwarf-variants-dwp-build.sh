#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), private current-LLVM fixture packager.
set -eu
[ "$#" = 5 ] || {
    echo "Usage: $0 GCC16_DRIVER SYSROOT LLVM_SOURCE LLVM_BUILD NEW_WORK" >&2
    exit 2
}
cc=$1 sysroot=$2 source=$3 build=$4 work=$5
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cxx=${CXX:-${cc%gcc}g++}
source=$(CDPATH= cd -- "$source" && pwd)
build=$(CDPATH= cd -- "$build" && pwd)
grep -q 'LLVM_VERSION_STRING "23.1.2"' "$build/include/llvm/Config/llvm-config.h"
[ -f "$build/lib/libLLVM.so.23.1" ]
mkdir "$work"
work=$(CDPATH= cd -- "$work" && pwd)
mkdir -p "$work/llvm/lib/DWP"
cp "$source/llvm/lib/DWP/DWP.cpp" "$work/llvm/lib/DWP/DWP.cpp"
(cd "$work"; patch -p1 < "$here/dwarf-variants-llvm-dwp.patch")
"$cxx" --version > "$work/compiler.txt"
compile()
{
    "$cxx" --sysroot="$sysroot" -std=c++17 -O2 -fPIC -fno-exceptions -funwind-tables \
        -DLLVM_EXPORTS -D_GLIBCXX_USE_CXX11_ABI=1 -D__STDC_CONSTANT_MACROS \
        -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS \
        -I"$source/llvm/lib/DWP" -I"$build/tools/llvm-dwp" \
        -I"$build/include" -I"$source/llvm/include" -c "$1" -o "$2"
}
compile "$work/llvm/lib/DWP/DWP.cpp" "$work/DWP.o"
compile "$source/llvm/tools/llvm-dwp/llvm-dwp.cpp" "$work/tool.o"
compile "$build/tools/llvm-dwp/llvm-dwp-driver.cpp" "$work/driver.o"
"$cxx" --sysroot="$sysroot" -B"$sysroot/usr/pkg/gcc16/lib/gcc/aarch64--netbsd/16.2.0/" \
    "$work/tool.o" "$work/driver.o" "$work/DWP.o" \
    -L"$build/lib" -L"$sysroot/usr/pkg/gcc16/lib" \
    -Wl,-rpath,/usr/pkg/gcc16/lib -Wl,-rpath,/usr/pkg/lib -lLLVM -lpthread \
    -o "$work/llvm-dwp"
printf 'Private fixture tool: %s/llvm-dwp\n' "$work"
