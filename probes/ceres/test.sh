#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: test.sh ABS_WORK' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
prefix=$work/install
[ -d "$prefix" ] && [ -d "$work/logs" ] || { echo 'The installed probe is missing.' >&2; exit 2; }
# Refuse a reused consumer build: cached package/compiler selections are evidence too.
[ ! -e "$work/test-build" ] || { echo 'Consumer build already exists; preserve it and use a new path.' >&2; exit 2; }
CXX=$(cat "$work/logs/cxx.txt")
[ -x "$CXX" ] || { echo 'The recorded C++ compiler is missing.' >&2; exit 2; }
LD_LIBRARY_PATH=$prefix/lib
export LD_LIBRARY_PATH
cmake -S "$recipe/tests" -B "$work/test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DPROBE_PREFIX="$prefix" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF \
    > "$work/logs/consumer-configure.log" 2>&1 || { cat "$work/logs/consumer-configure.log" >&2; exit 1; }
cmake --build "$work/test-build" --parallel 1 > "$work/logs/consumer-build.log" 2>&1 || {
    cat "$work/logs/consumer-build.log" >&2; exit 1;
}
ctest --test-dir "$work/test-build" --output-on-failure --verbose > "$work/logs/consumer-test.log" 2>&1 || {
    cat "$work/logs/consumer-test.log" >&2; exit 1;
}
cat "$work/logs/consumer-test.log"
ldd "$work/test-build/ceres-contract" > "$work/logs/installed-linkage.txt"
grep -F "$prefix/lib/libceres.so" "$work/logs/installed-linkage.txt" >/dev/null || {
    echo 'The consumer did not load the installed Ceres library.' >&2; exit 1;
}
if grep -E 'not found|libc[+][+]' "$work/logs/installed-linkage.txt" >/dev/null; then
    echo 'Missing dependency or mixed C++ runtime.' >&2; exit 1;
fi
expected_runtime=$("$CXX" -print-file-name=libstdc++.so)
[ -f "$expected_runtime" ] || { echo 'Compiler did not identify its C++ runtime.' >&2; exit 1; }
expected_runtime=$(realpath "$expected_runtime")
loaded_runtime=$(awk '/libstdc[+][+]/ {print $3}' "$work/logs/installed-linkage.txt")
[ -n "$loaded_runtime" ] && [ "$(printf '%s\n' "$loaded_runtime" | wc -l | tr -d ' ')" = 1 ] || {
    echo 'Expected exactly one loaded C++ runtime.' >&2; exit 1;
}
[ "$(realpath "$loaded_runtime")" = "$expected_runtime" ] || {
    echo 'Loaded C++ runtime differs from the recorded compiler runtime.' >&2; exit 1;
}
echo 'PASS installed library and coherent C++ runtime linkage'
