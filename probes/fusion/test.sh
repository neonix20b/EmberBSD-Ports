#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: test.sh ABS_WORK' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple path.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
prefix=$work/install
[ -d "$prefix" ] && [ -d "$work/logs" ] || { echo 'Missing installation.' >&2; exit 2; }
run()
{
    stage=$1
    shift
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    cat "$work/logs/$stage.log"
    [ "$status" = 0 ] || exit "$status"
}
run consumer-configure cmake -S "$recipe/tests" -B "$work/test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DPROBE_PREFIX="$prefix" -DCMAKE_BUILD_RPATH="$prefix/lib"
run consumer-build cmake --build "$work/test-build" --parallel 1
run contracts ctest --test-dir "$work/test-build" --verbose
case $(uname -s) in
    Darwin) DYLD_PRINT_LIBRARIES=1 "$work/test-build/fusion-contract" static \
        > "$work/logs/linkage-contract.txt" 2> "$work/logs/installed-linkage.txt" ;;
    *) ldd "$work/test-build/fusion-contract" > "$work/logs/installed-linkage.txt" ;;
esac
if grep -q 'not found' "$work/logs/installed-linkage.txt"; then
    echo 'Unresolved library.' >&2; exit 1
fi
grep -F "$prefix/lib/libFusion" "$work/logs/installed-linkage.txt" >/dev/null || {
    echo 'Incorrect installed Fusion linkage.' >&2; exit 1;
}
