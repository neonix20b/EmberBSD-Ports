#!/bin/sh
set -eu
[ "$#" -eq 3 ] || {
    echo 'Usage: qt-consumer.sh GCC_PREFIX QT_PKG_CONFIG_DIRECTORY NEW_OUTPUT_DIRECTORY' >&2
    exit 2
}
prefix=$1
qt_pc=$2
output=$3
for path in "$prefix" "$qt_pc" "$output"; do
    case "$path" in /*) ;; *) echo 'Absolute paths required.' >&2; exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./-]*) echo 'Unsafe path.' >&2; exit 2 ;; esac
done
[ "$(uname -s)" = NetBSD ] || exit 2
[ ! -e "$output" ] && [ ! -L "$output" ] || exit 2
[ -z "${LD_LIBRARY_PATH:-}${LD_PRELOAD:-}" ] || exit 2
unset GCC_EXEC_PREFIX COMPILER_PATH LIBRARY_PATH CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH
[ "$("$prefix/bin/g++" -dumpfullversion)" = 16.2.0 ]
source=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$output"
PKG_CONFIG_PATH=$qt_pc
export PKG_CONFIG_PATH
pkg-config --modversion Qt6Core > "$output/qt-version.txt"
# pkg-config emits compiler/linker arguments; intentional field splitting.
"$prefix/bin/g++" -std=c++20 -O2 -fPIC -Wall -Wextra -Werror \
    $(pkg-config --cflags Qt6Core) "$source/qt-consumer.cc" \
    $(pkg-config --libs Qt6Core) -o "$output/qt-consumer"
readelf -d "$output/qt-consumer" > "$output/dynamic.txt"
ldd "$output/qt-consumer" > "$output/ldd.txt"
"$output/qt-consumer" > "$output/loaded.txt"
sh "$source/check-runtime.sh" "$prefix" "$output"
echo 'PASS: Qt string boundary and one matching GCC16 runtime'
