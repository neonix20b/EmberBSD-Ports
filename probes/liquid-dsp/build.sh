#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
umask 022
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: FFTW_PREFIX=ABS_PREFIX build.sh ABS_NEW_WORK [ABS_CACHE]' >&2; exit 2; }
work=$1
for directory in "$@" "${FFTW_PREFIX:-}"; do
    case "$directory" in /*) ;; *) echo 'Use absolute paths, including required FFTW_PREFIX.' >&2; exit 2 ;; esac
    case "$directory" in *[!a-zA-Z0-9_./-]*) echo 'Use simple paths.' >&2; exit 2 ;; esac
done
[ ! -e "$work" ] && [ ! -L "$work" ] || { echo 'Work path already exists.' >&2; exit 2; }
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || exit 2
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
for tool in cmake ninja tar patch "${CC:-cc}" nm; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
if command -v sha256 >/dev/null; then
    digest() { sha256 -q "$1"; }
else
    command -v shasum >/dev/null || exit 2
    digest() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
fi
[ -f "$FFTW_PREFIX/share/ember-fftw/profile.txt" ] && \
    grep -qx '3.3.11 double float pthread shared' "$FFTW_PREFIX/share/ember-fftw/profile.txt" && \
    [ -f "$FFTW_PREFIX/include/fftw3.h" ] && \
    grep -qx 'Version: 3.3.11' "$FFTW_PREFIX/lib/pkgconfig/fftw3f.pc" || {
    echo 'Required common FFTW 3.3.11 profile is missing.' >&2; exit 2;
}
case $(uname -s) in Darwin) fftw_library=$FFTW_PREFIX/lib/libfftw3f.dylib ;;
    *) fftw_library=$FFTW_PREFIX/lib/libfftw3f.so ;; esac
[ -f "$fftw_library" ] || { echo 'Required shared fftw3f library is missing.' >&2; exit 2; }
[ "$#" = 2 ] || command -v curl >/dev/null
mkdir "$work"
mkdir "$work/src" "$work/archives" "$work/logs"
prefix=$work/install
run()
{
    stage=$1
    shift
    printf '%s\n' "$stage"
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then tail -60 "$work/logs/$stage.log" >&2; exit "$status"; fi
}
while read -r name expected url; do
    if [ "$#" = 2 ]; then cp "$2/$name" "$work/archives/$name"
    else curl -fLsS --connect-timeout 20 --max-time 900 "$url" -o "$work/archives/$name"; fi
    [ "$(digest "$work/archives/$name")" = "$expected" ] || { echo "Checksum mismatch: $name" >&2; exit 2; }
    printf '%s %s %s\n' "$name" "$expected" "$url" >> "$work/logs/sources.txt"
done < "$recipe/sources.tsv"
tar -xf "$work/archives/liquid-dsp-1.8.3.tar.gz" -C "$work/src"
source=$work/src/liquid-dsp-1.8.3
{ uname -a; "${CC:-cc}" --version; cmake --version; ninja --version; } > "$work/logs/tools.txt"
configure()
{
    cmake -S "$source" -B "$1" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib \
        -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF -DBUILD_EXAMPLES=OFF \
        -DBUILD_AUTOTESTS=OFF -DBUILD_BENCHMARKS=OFF -DBUILD_SANDBOX=OFF -DBUILD_DOC=OFF \
        -DENABLE_TIMESTAMPS=OFF -DENABLE_SIMD=OFF -DFIND_SIMD=OFF \
        -DFIND_FFTW=ON -DCMAKE_REQUIRE_FIND_PACKAGE_fftw3f=ON \
        -Dfftw3f_INCLUDE_DIR="$FFTW_PREFIX/include" -Dfftw3f_LIBRARY="$fftw_library" \
        -DCMAKE_INSTALL_RPATH="$FFTW_PREFIX/lib"
}
run baseline-configure configure "$work/baseline-build"
# The original configured header falsely selects the built-in FFT backend.
if "${CC:-cc}" -std=c11 -I"$source/include" -I"$work/baseline-build" \
    -I"$FFTW_PREFIX/include" -c "$recipe/tests/backend-selection.c" \
    -o "$work/baseline-backend.o" > "$work/logs/backend-baseline.txt" 2>&1; then
    echo 'Baseline unexpectedly selected FFTW; review patch.' >&2; exit 1
fi
grep -F FFTW_BACKEND_REQUIRED "$work/logs/backend-baseline.txt" >/dev/null
run fftw-selection-patch patch -d "$source" -p1 < "$recipe/patches/cmake-fftw-selection.patch"
digest "$recipe/patches/cmake-fftw-selection.patch" > "$work/logs/patch.sha256"
run liquid-configure configure "$work/liquid-build"
run backend-compile "${CC:-cc}" -std=c11 -I"$source/include" -I"$work/liquid-build" \
    -I"$FFTW_PREFIX/include" "$recipe/tests/backend-selection.c" \
    "$fftw_library" -Wl,-rpath,"$FFTW_PREFIX/lib" -lm -o "$work/backend-selection"
run backend-patched "$work/backend-selection"
run liquid-build cmake --build "$work/liquid-build" --parallel "$jobs"
run liquid-install cmake --install "$work/liquid-build"
case $(uname -s) in Darwin) liquid_library=$prefix/lib/libliquid.dylib ;;
    *) liquid_library=$prefix/lib/libliquid.so ;; esac
nm -u "$liquid_library" > "$work/logs/fftw-imports.txt"
for symbol in fftwf_plan_dft_1d fftwf_execute fftwf_destroy_plan; do
    grep -w "$symbol" "$work/logs/fftw-imports.txt" >/dev/null || \
        grep -w "_$symbol" "$work/logs/fftw-imports.txt" >/dev/null || {
        echo "Missing actual FFTW backend import: $symbol" >&2; exit 1;
    }
done
mkdir -p "$prefix/share/ember-liquid-dsp/licenses"
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$prefix/share/ember-liquid-dsp/"
cp "$source/LICENSE" "$prefix/share/ember-liquid-dsp/licenses/liquid-dsp-MIT"
printf '%s\n' "$FFTW_PREFIX" > "$prefix/share/ember-liquid-dsp/fftw-prefix.txt"
echo "Installed in $prefix; run test.sh next."
