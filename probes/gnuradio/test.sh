#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: test.sh ABS_WORK' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple path.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
prefix=$work/install
[ -f "$prefix/lib/cmake/gnuradio/GnuradioConfig.cmake" ] || { echo 'Missing installation.' >&2; exit 2; }
fftw=$(cat "$work/fftw-prefix.txt")
volk=$(cat "$work/volk-prefix.txt")
cmake=${CMAKE:-cmake}
ctest=${CTEST:-ctest}
build_as_kib=${BUILD_AS_KIB:-1572864}
case "$build_as_kib" in ''|0|*[!0-9]*) echo 'BUILD_AS_KIB must be positive.' >&2; exit 2 ;; esac
ulimit -v "$build_as_kib"
LD_LIBRARY_PATH="$prefix/lib:$volk/lib:$fftw/lib:/usr/pkg/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
GR_PREFS_PATH=$work/test-state/prefs
GR_CACHE_PATH=$work/test-state/cache
GR_STATE_PATH=$work/test-state/state
VOLK_CONFIGPATH=$work/test-state
TMPDIR=$work/test-state/tmp
TMP=$TMPDIR
export LD_LIBRARY_PATH GR_PREFS_PATH GR_CACHE_PATH GR_STATE_PATH VOLK_CONFIGPATH TMPDIR TMP
unset GR_PREFIX VOLK_GENERIC
mkdir -p "$GR_PREFS_PATH" "$GR_CACHE_PATH" "$GR_STATE_PATH" "$VOLK_CONFIGPATH/volk" "$TMPDIR"
# VOLK otherwise falls back to HOME when this exact file is absent.
: > "$VOLK_CONFIGPATH/volk/volk_config"
"$cmake" -S "$recipe/tests" -B "$work/test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DPROBE_PREFIX="$prefix" -DFFTW_PREFIX="$fftw" -DVOLK_PREFIX="$volk" \
    -DCMAKE_BUILD_RPATH="$prefix/lib;$volk/lib;$fftw/lib;/usr/pkg/lib"
"$cmake" --build "$work/test-build" --parallel 1
status=0
"$ctest" --test-dir "$work/test-build" --verbose > "$work/logs/contracts.txt" 2>&1 || status=$?
cat "$work/logs/contracts.txt"
[ "$status" = 0 ] || exit "$status"
cat "$GR_PREFS_PATH/prefs/vmcircbuf_default_factory" > "$work/logs/buffer-factory.txt"
printf 'Selected upstream buffer factory: %s\n' "$(cat "$work/logs/buffer-factory.txt")"
ldd "$work/test-build/gnuradio-contract" > "$work/logs/installed-linkage.txt"
if grep -q 'not found' "$work/logs/installed-linkage.txt"; then
    echo 'Unresolved library.' >&2; exit 1
fi
for component in runtime pmt blocks fft filter analog digital channels; do
    grep -F "$prefix/lib/libgnuradio-$component.so" "$work/logs/installed-linkage.txt" >/dev/null || {
        echo "Incorrect installed linkage: $component" >&2; exit 1;
    }
done
for library in "$prefix/lib/libspdlog.so" "$volk/lib/libvolk.so" "$volk/lib/libfmt.so" \
    "$fftw/lib/libfftw3f.so" /usr/lib/libstdc++.so /usr/lib/libgcc_s.so; do
    grep -F "$library" "$work/logs/installed-linkage.txt" >/dev/null || {
        echo "Incorrect dependency linkage: $library" >&2; exit 1;
    }
done
readelf -d "$prefix/lib/libgnuradio-runtime.so" > "$work/logs/runtime-dynamic.txt"
grep -E 'NEEDED.*\[librt\.so\.' "$work/logs/runtime-dynamic.txt" >/dev/null || {
    echo 'Runtime does not declare its NetBSD shared-memory dependency.' >&2; exit 1;
}
if grep -E 'libpython|libQt|libuhd|libSoapySDR|libsndfile|libFLAC|libogg|libvorbis|libopus|libmpg123|libmp3lame' "$work/logs/installed-linkage.txt"; then
    echo 'Unexpected dependency outside this headless profile.' >&2; exit 1
fi
echo 'Installed GNU Radio flowgraph, FFT, failure/stop contracts and linkage passed.'
