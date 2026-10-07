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
# Do not permit caller library search paths to override the selected profile.
LD_LIBRARY_PATH="$prefix/lib"
export LD_LIBRARY_PATH
cmake -S "$recipe/tests" -B "$work/test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DPROBE_PREFIX="$prefix" -DCMAKE_BUILD_RPATH="$prefix/lib"
cmake --build "$work/test-build" --parallel 1
status=0
ctest --test-dir "$work/test-build" --verbose > "$work/logs/contracts.txt" 2>&1 || status=$?
cat "$work/logs/contracts.txt"
[ "$status" = 0 ] || exit "$status"
for kind in double float; do
    case $(uname -s) in
        Darwin) DYLD_PRINT_LIBRARIES=1 "$work/test-build/fftw-$kind" \
            > "$work/logs/linkage-$kind-run.txt" 2> "$work/logs/linkage-$kind.txt" ;;
        *) ldd "$work/test-build/fftw-$kind" > "$work/logs/linkage-$kind.txt" ;;
    esac
    if grep -q 'not found' "$work/logs/linkage-$kind.txt"; then exit 1; fi
    if [ "$kind" = double ]; then library=libfftw3; else library=libfftw3f; fi
    for suffix in . _threads.; do
        grep -F "$prefix/lib/$library$suffix" "$work/logs/linkage-$kind.txt" >/dev/null || {
            echo "Incorrect installed linkage: $library$suffix" >&2; exit 1;
        }
    done
done
