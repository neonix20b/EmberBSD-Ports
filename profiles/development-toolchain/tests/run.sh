#!/bin/sh
# Check an installed candidate explicitly; never alter compiler selection.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: run.sh GCC_PREFIX NEW_OUTPUT_DIRECTORY' >&2; exit 2; }
prefix=$1
output=$2
for path in "$prefix" "$output"; do
    case "$path" in /*) ;; *) echo 'Absolute paths required.' >&2; exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./-]*) echo 'Unsafe path.' >&2; exit 2 ;; esac
done
[ "$(uname -s)" = NetBSD ] || { echo 'Native NetBSD acceptance only.' >&2; exit 2; }
[ ! -e "$output" ] && [ ! -L "$output" ] || { echo 'Output already exists.' >&2; exit 2; }
[ -z "${LD_LIBRARY_PATH:-}${LD_PRELOAD:-}" ] || { echo 'Remove loader overrides.' >&2; exit 2; }
unset GCC_EXEC_PREFIX COMPILER_PATH LIBRARY_PATH CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH
cc=$prefix/bin/gcc
cxx=$prefix/bin/g++
[ "$("$cc" -dumpfullversion)" = 16.2.0 ]
[ "$("$cxx" -dumpfullversion)" = 16.2.0 ]
source=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$output"
"$cc" -v 2> "$output/compiler.txt"
"$cc" -dumpmachine >> "$output/compiler.txt"
"$cc" -std=c11 -O2 -Wall -Wextra -Werror -pthread \
    "$source/atomic-tls.c" -o "$output/atomic-tls"
"$output/atomic-tls"
"$cxx" -std=c++20 -O2 -Wall -Wextra -Werror -fPIC -shared \
    "$source/boundary.cc" -Wl,-soname,libboundary.so -o "$output/libboundary.so"
"$cxx" -std=c++20 -O2 -Wall -Wextra -Werror -pthread \
    "$source/boundary-main.cc" -L"$output" -Wl,-rpath,"$output" \
    -lboundary -o "$output/boundary"
readelf -d "$output/boundary" "$output/libboundary.so" > "$output/dynamic.txt"
ldd "$output/boundary" > "$output/ldd.txt"
"$output/boundary" > "$output/loaded.txt"
sh "$source/check-runtime.sh" "$prefix" "$output"
echo 'PASS: native C11 atomics, C/C++ TLS, threads, C++20, DSO strings/unwind and loaded runtimes'
