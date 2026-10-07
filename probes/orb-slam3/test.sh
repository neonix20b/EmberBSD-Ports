#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 2 ] || { echo 'Usage: test.sh ABS_WORK ABS_COMMON_PREFIX' >&2; exit 2; }
work=$1
common=$2
opencv=${OPENCV_PREFIX:-$common}
for directory in "$@" "$opencv"; do
    case "$directory" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$directory" in *[!a-zA-Z0-9_./-]*) echo 'Use simple paths.' >&2; exit 2 ;; esac
done
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
prefix=$work/install
[ -d "$prefix" ] && [ -d "$work/logs" ] || { echo 'Missing installation.' >&2; exit 2; }
run()
{
    stage=$1; shift
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    cat "$work/logs/$stage.log"
    [ "$status" = 0 ] || exit "$status"
}
run consumer-configure cmake -S "$recipe/tests" -B "$work/test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DPROBE_PREFIX="$prefix" -DCOMMON_PREFIX="$common" \
    -DOPENCV_PREFIX="$opencv" \
    -DCMAKE_BUILD_RPATH="$prefix/lib/orb-slam3;$opencv/lib;$common/lib;/usr/pkg/lib"
run consumer-build cmake --build "$work/test-build" --parallel 1
run contracts ctest --test-dir "$work/test-build" --verbose
ldd "$work/test-build/orb-contract" > "$work/logs/installed-linkage.txt"
if grep -q 'not found' "$work/logs/installed-linkage.txt"; then
    echo 'Unresolved library.' >&2; exit 1
fi
for library in ORB_SLAM3 DBoW2 g2o; do
    grep -F "$prefix/lib/orb-slam3/lib$library.so" "$work/logs/installed-linkage.txt" >/dev/null || {
        echo "Incorrect installed linkage: $library" >&2; exit 1;
    }
done
grep -F "$opencv/lib/libopencv_core.so" "$work/logs/installed-linkage.txt" >/dev/null || {
    echo 'Incorrect common OpenCV linkage.' >&2; exit 1;
}
awk -v prefix="$opencv/lib/" '/libopencv_/ { if (index($0, prefix) == 0) bad=1 } END { exit bad }' \
    "$work/logs/installed-linkage.txt" || {
    echo 'An OpenCV dependency escaped the selected provider.' >&2; exit 1;
}
if grep -Ei 'pangolin|libGL\.|libEGL\.|opencv_highgui' "$work/logs/installed-linkage.txt"; then
    echo 'Unexpected viewer dependency in headless profile.' >&2; exit 1
fi
