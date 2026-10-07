#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: test.sh ABS_WORK' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
prefix=$work/install
[ -d "$prefix" ] && [ -d "$work/logs" ] || exit 2
fftw_prefix=$(cat "$prefix/share/ember-liquid-dsp/fftw-prefix.txt")
case "$fftw_prefix" in /*) ;; *) exit 2 ;; esac
case "$fftw_prefix" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
LD_LIBRARY_PATH="$prefix/lib:$fftw_prefix/lib"
export LD_LIBRARY_PATH
cmake -S "$recipe/tests" -B "$work/test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DPROBE_PREFIX="$prefix" \
    -DCMAKE_BUILD_RPATH="$prefix/lib;$fftw_prefix/lib"
cmake --build "$work/test-build" --parallel 1
status=0
ctest --test-dir "$work/test-build" --verbose > "$work/logs/contracts.txt" 2>&1 || status=$?
cat "$work/logs/contracts.txt"
[ "$status" = 0 ] || exit "$status"
case $(uname -s) in
    Darwin) DYLD_PRINT_LIBRARIES=1 "$work/test-build/liquid-contract" spectrum \
        > "$work/logs/linkage-run.txt" 2> "$work/logs/installed-linkage.txt" ;;
    *) ldd "$work/test-build/liquid-contract" > "$work/logs/installed-linkage.txt" ;;
esac
if grep -q 'not found' "$work/logs/installed-linkage.txt"; then exit 1; fi
for library in "$prefix/lib/libliquid." "$fftw_prefix/lib/libfftw3f."; do
    grep -F "$library" "$work/logs/installed-linkage.txt" >/dev/null || {
        echo "Incorrect installed linkage: $library" >&2; exit 1;
    }
done
