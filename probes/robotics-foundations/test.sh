#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: test.sh WORK' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
prefix=$work/install
opencv_prefix=${OPENCV_PREFIX:-$prefix}
case "$opencv_prefix" in /*) ;; *) echo 'Use an absolute OpenCV prefix.' >&2; exit 2 ;; esac
test_build=${TEST_BUILD:-$work/test-build}
case "$test_build" in /*) ;; *) echo 'Use an absolute consumer build path.' >&2; exit 2 ;; esac
printf '%s\n' "$opencv_prefix" > "$work/logs/test-opencv-prefix.txt"
PATH="$prefix/sbin:$prefix/bin:$PATH"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/share/pkgconfig"
LD_LIBRARY_PATH="$opencv_prefix/lib:$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH PKG_CONFIG_PATH LD_LIBRARY_PATH
cmake -S "$recipe/tests" -B "$test_build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$opencv_prefix;$prefix" \
    -DOpenCV_DIR="$opencv_prefix/lib/cmake/opencv5" \
    -DGPSD_EXECUTABLE="$prefix/sbin/gpsd"
cmake --build "$test_build" --parallel 1
ctest --test-dir "$test_build" --output-on-failure
for binary in "$test_build/eigen-contract" "$test_build/opencv-contract" \
    "$test_build/gpsd-contract" "$prefix/sbin/gpsd"; do
    ldd "$binary"
done > "$work/logs/installed-linkage.txt"
grep -F "$opencv_prefix/lib/libopencv_core" "$work/logs/installed-linkage.txt" >/dev/null || {
    echo 'Foundation consumer did not load the selected OpenCV provider.' >&2; exit 1;
}
if grep -q 'not found' "$work/logs/installed-linkage.txt"; then
    echo 'Missing runtime dependency.' >&2
    exit 1
fi
