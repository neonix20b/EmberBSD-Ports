#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: test.sh WORK' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
prefix=$work/install
PATH="$prefix/sbin:$prefix/bin:$PATH"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/share/pkgconfig"
LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH PKG_CONFIG_PATH LD_LIBRARY_PATH
cmake -S "$recipe/tests" -B "$work/test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$prefix" \
    -DGPSD_EXECUTABLE="$prefix/sbin/gpsd"
cmake --build "$work/test-build" --parallel 1
ctest --test-dir "$work/test-build" --output-on-failure
for binary in "$work/test-build/eigen-contract" "$work/test-build/opencv-contract" \
    "$work/test-build/gpsd-contract" "$prefix/sbin/gpsd"; do
    ldd "$binary"
done > "$work/logs/installed-linkage.txt"
if grep -q 'not found' "$work/logs/installed-linkage.txt"; then
    echo 'Missing runtime dependency.' >&2
    exit 1
fi
