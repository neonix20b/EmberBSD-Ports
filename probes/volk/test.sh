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
cmake=${CMAKE:-cmake}
ctest=${CTEST:-ctest}
LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
# Isolate preferences without changing HOME or running a profiler in the desktop session.
VOLK_CONFIGPATH=$work/test-config
export VOLK_CONFIGPATH
mkdir -p "$VOLK_CONFIGPATH"
unset VOLK_GENERIC volk_32f_x2_dot_prod_32f volk_32f_x2_multiply_32f volk_32fc_magnitude_32f
"$cmake" -S "$recipe/tests" -B "$work/test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DPROBE_PREFIX="$prefix" -DCMAKE_BUILD_RPATH="$prefix/lib"
"$cmake" --build "$work/test-build" --parallel 1
status=0
"$ctest" --test-dir "$work/test-build" --verbose > "$work/logs/contracts.txt" 2>&1 || status=$?
cat "$work/logs/contracts.txt"
[ "$status" = 0 ] || exit "$status"
"$prefix/bin/volk-config-info" --version --all-machines --machine --alignment > "$work/logs/dispatch.txt"
ldd "$work/test-build/volk-contract" > "$work/logs/installed-linkage.txt"
ldd "$prefix/bin/volk_profile" > "$work/logs/profiler-linkage.txt"
if grep -q 'not found' "$work/logs/installed-linkage.txt" "$work/logs/profiler-linkage.txt"; then
    echo 'Unresolved library.' >&2; exit 1
fi
grep -F "$prefix/lib/libvolk" "$work/logs/installed-linkage.txt" >/dev/null || {
    echo 'Incorrect installed VOLK linkage.' >&2; exit 1;
}
for library in libvolk libfmt; do
    grep -F "$prefix/lib/$library" "$work/logs/profiler-linkage.txt" >/dev/null || {
        echo "Incorrect installed profiler linkage: $library" >&2; exit 1;
    }
done
echo 'Installed VOLK contracts and linkage passed.'
