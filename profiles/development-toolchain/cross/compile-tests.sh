#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; reuse the native C/C++ acceptance sources for a cross build.
set -eu
[ "$#" -eq 3 ] || { echo 'Usage: compile-tests.sh CROSS_PREFIX SYSROOT NEW_OUTPUT' >&2; exit 2; }
prefix=$1 sysroot=$2 out=$3
for path in "$@"; do
    case "$path" in /*) ;; *) echo 'Absolute paths required.' >&2; exit 2;; esac
    case "$path" in *[!A-Za-z0-9_./-]*) echo 'Use simple paths.' >&2; exit 2;; esac
done
[ ! -e "$out" ] && [ ! -L "$out" ] || { echo 'Output already exists.' >&2; exit 2; }
source=$(CDPATH= cd -- "$(dirname -- "$0")/../tests" && pwd -P)
cross_source=$(CDPATH= cd -- "$(dirname -- "$0")/tests" && pwd -P)
cc=$prefix/bin/aarch64--netbsd-gcc
cxx=$prefix/bin/aarch64--netbsd-g++
[ "$("$cc" -dumpfullversion)" = 16.2.0 ]
[ "$("$cxx" -dumpmachine)" = aarch64--netbsd ]
unset GCC_EXEC_PREFIX COMPILER_PATH LIBRARY_PATH CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH
mkdir "$out"
"$cc" -v 2> "$out/compiler.txt"
set -- --sysroot="$sysroot" -B"$sysroot/usr/pkg/gcc16/lib/gcc/aarch64--netbsd/16.2.0/" \
    -L"$sysroot/usr/pkg/gcc16/lib" -Wl,-rpath,/usr/pkg/gcc16/lib
"$cc" "$@" -std=c11 -O2 -Wall -Wextra -Werror -pthread "$source/atomic-tls.c" -o "$out/atomic-tls"
"$cc" "$@" -std=c11 -O2 -flto -Wall -Wextra -Werror -pthread "$source/atomic-tls.c" -o "$out/atomic-tls-lto"
set -- "$@" -isystem "$sysroot/usr/pkg/gcc16/include/c++" \
    -isystem "$sysroot/usr/pkg/gcc16/include/c++/aarch64--netbsd" \
    -isystem "$sysroot/usr/pkg/gcc16/include/c++/backward"
"$cxx" "$@" -std=c++20 -O3 -Wall -Wextra -Werror \
    -c "$cross_source/float-constexpr.cc" -o "$out/float-constexpr.o"
"$cxx" "$@" -std=c++20 -O2 -Wall -Wextra -Werror -fPIC -shared \
    "$source/boundary.cc" -Wl,-soname,libboundary.so -o "$out/libboundary.so"
"$cxx" "$@" -std=c++20 -O2 -Wall -Wextra -Werror -pthread \
    "$source/boundary-main.cc" -L"$out" '-Wl,-rpath,$ORIGIN' -lboundary -o "$out/boundary"
"$prefix/bin/aarch64--netbsd-readelf" -d "$out/boundary" "$out/libboundary.so" > "$out/dynamic.txt"
if grep -F -e "$prefix" -e "$sysroot" -e "$out" "$out/dynamic.txt" | grep -E 'RPATH|RUNPATH|NEEDED'; then
    echo 'Host path leaked into target dynamic dependencies.' >&2; exit 1
fi
cp "$source/check-runtime.sh" "$out/"
cp "$source/../cross/run-target.sh" "$out/"
echo "Cross-compiled tests: $out; run run-target.sh on EmberBSD."
