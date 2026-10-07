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
LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
cmake -S "$recipe/tests" -B "$work/test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DPROBE_PREFIX="$prefix" -DCMAKE_BUILD_RPATH="$prefix/lib"
cmake --build "$work/test-build" --parallel 1
status=0
ctest --test-dir "$work/test-build" --output-on-failure > "$work/logs/contracts.txt" 2>&1 || status=$?
cat "$work/logs/contracts.txt"
[ "$status" = 0 ] || exit "$status"
case $(uname -s) in
    Darwin) (cd "$work/test-build" && DYLD_PRINT_LIBRARIES=1 ./mcap-contract none) \
        > "$work/logs/linkage-contract.txt" 2> "$work/logs/installed-linkage.txt" ;;
    *) ldd "$work/test-build/mcap-contract" > "$work/logs/installed-linkage.txt" ;;
esac
if grep -q 'not found' "$work/logs/installed-linkage.txt"; then
    echo 'Unresolved library.' >&2; exit 1
fi
for library in liblz4 libzstd; do
    grep -F "$prefix/lib/$library" "$work/logs/installed-linkage.txt" >/dev/null || {
        echo "Incorrect installed linkage: $library" >&2; exit 1;
    }
done
