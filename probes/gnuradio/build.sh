#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
umask 022
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: build.sh ABS_NEW_WORK [ABS_CACHE]' >&2; exit 2; }
work=$1
: "${FFTW_PREFIX:?Set FFTW_PREFIX to the tested FFTW 3.3.11 installation}"
: "${VOLK_PREFIX:?Set VOLK_PREFIX to the tested VOLK 3.3.0 and fmt 12.2.0 installation}"
for directory in "$@" "$FFTW_PREFIX" "$VOLK_PREFIX"; do
    case "$directory" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$directory" in *[!a-zA-Z0-9_./-]*) echo 'Use simple paths.' >&2; exit 2 ;; esac
done
[ ! -e "$work" ] && [ ! -L "$work" ] || { echo 'Work path already exists.' >&2; exit 2; }
case "$(uname -s):$(uname -p)" in
    NetBSD:aarch64) ;;
    *) echo 'This profile requires native NetBSD/aarch64.' >&2; exit 2 ;;
esac
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || exit 2
build_as_kib=${BUILD_AS_KIB:-1572864}
case "$build_as_kib" in ''|0|*[!0-9]*) echo 'BUILD_AS_KIB must be positive.' >&2; exit 2 ;; esac
ulimit -v "$build_as_kib"
export BUILD_AS_KIB=$build_as_kib
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
cmake=${CMAKE:-cmake}
python=${PYTHON_EXECUTABLE:-python3}
for tool in "$cmake" ninja tar patch "$python" pkg-config; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
if command -v sha256 >/dev/null; then
    digest() { sha256 -q "$1"; }
else
    command -v shasum >/dev/null || { echo 'sha256 or shasum required.' >&2; exit 2; }
    digest() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
fi
PKG_CONFIG_PATH="$FFTW_PREFIX/lib/pkgconfig:$VOLK_PREFIX/lib/pkgconfig:/usr/pkg/lib/pkgconfig"
export PKG_CONFIG_PATH
[ "$(pkg-config --modversion fftw3f)" = 3.3.11 ] || { echo 'FFTW float version mismatch.' >&2; exit 2; }
# Upstream's .pc file advertises SOVERSION (3.3), not the full release version.
[ "$(pkg-config --modversion volk)" = 3.3 ] &&
    [ "$("$VOLK_PREFIX/bin/volk-config-info" --version)" = 3.3.0 ] || {
    echo 'VOLK ABI or release version mismatch.' >&2; exit 2;
}
[ "$(pkg-config --modversion fmt)" = 12.2.0 ] || { echo 'fmt version mismatch.' >&2; exit 2; }
for library in libfftw3f.so libfftw3f_threads.so; do
    [ -f "$FFTW_PREFIX/lib/$library" ] || { echo "Missing FFTW library: $library" >&2; exit 2; }
done
[ -f /usr/pkg/lib/cmake/Boost-1.91.0/BoostConfig.cmake ] || { echo 'Common Boost 1.91.0 required.' >&2; exit 2; }
[ "$(pkg-config --modversion gmp)" = 6.3.0 ] || { echo 'Common GMP 6.3.0 required.' >&2; exit 2; }
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
    if [ "$status" -ne 0 ]; then
        tail -70 "$work/logs/$stage.log" >&2
        exit "$status"
    fi
}
while read -r name expected url; do
    if [ "$#" = 2 ]; then
        cp "$2/$name" "$work/archives/$name"
    else
        curl -fLsS --connect-timeout 20 --max-time 900 "$url" -o "$work/archives/$name"
    fi
    actual=$(digest "$work/archives/$name")
    [ "$actual" = "$expected" ] || { echo "Checksum mismatch: $name" >&2; exit 2; }
    printf '%s %s %s\n' "$name" "$actual" "$url" >> "$work/logs/sources.txt"
done < "$recipe/sources.tsv"
while read -r name expected; do
    [ "$(digest "$recipe/$name")" = "$expected" ] || { echo "Patch checksum mismatch: $name" >&2; exit 2; }
done < "$recipe/patches.tsv"
while read -r name expected url; do
    tar -mxf "$work/archives/$name" -C "$work/src"
done < "$recipe/sources.tsv"
while read -r name expected; do
    run "$(basename "$name")" patch -d "$work/src/gnuradio-3.10.12.0" -p0 < "$recipe/$name"
done < "$recipe/patches.tsv"
{ uname -a; "$cmake" --version; ninja --version; "$python" --version;
  pkg-config --modversion fftw3f volk fmt gmp;
  printf 'FFTW_PREFIX=%s\nVOLK_PREFIX=%s\n' "$FFTW_PREFIX" "$VOLK_PREFIX";
  printf 'BUILD_AS_KIB=%s\n' "$build_as_kib";
} > "$work/logs/tools.txt"
printf '%s\n' "$FFTW_PREFIX" > "$work/fftw-prefix.txt"
printf '%s\n' "$VOLK_PREFIX" > "$work/volk-prefix.txt"
if command -v pkg_info >/dev/null; then
    pkg_info | grep -E '^(boost-|gmp-|python|py[0-9]+-(mako|markupsafe|packaging))' >> "$work/logs/tools.txt"
fi
rpaths="$prefix/lib;$VOLK_PREFIX/lib;$FFTW_PREFIX/lib;/usr/pkg/lib"
run spdlog-configure "$cmake" -S "$work/src/spdlog-1.17.0" -B "$work/spdlog-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_RPATH="$rpaths" -Dfmt_DIR="$VOLK_PREFIX/lib/cmake/fmt" \
    -DSPDLOG_BUILD_SHARED=ON -DSPDLOG_FMT_EXTERNAL=ON -DSPDLOG_BUILD_EXAMPLE=OFF \
    -DSPDLOG_BUILD_TESTS=OFF -DSPDLOG_INSTALL=ON
run spdlog-build "$cmake" --build "$work/spdlog-build" --parallel "$jobs"
run spdlog-install "$cmake" --install "$work/spdlog-build"
run gnuradio-configure "$cmake" -S "$work/src/gnuradio-3.10.12.0" -B "$work/gnuradio-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_PREFIX_PATH="$prefix;$VOLK_PREFIX;$FFTW_PREFIX;/usr/pkg" \
    -DCMAKE_INSTALL_RPATH="$rpaths" -DCMAKE_BUILD_RPATH="$rpaths" \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF \
    -DBoost_DIR=/usr/pkg/lib/cmake/Boost-1.91.0 -Dspdlog_DIR="$prefix/lib/cmake/spdlog" \
    -Dfmt_DIR="$VOLK_PREFIX/lib/cmake/fmt" -DVolk_DIR="$VOLK_PREFIX/lib/cmake/volk" \
    -DFFTW3f_INCLUDE_DIRS="$FFTW_PREFIX/include" -DFFTW3f_LIBRARIES="$FFTW_PREFIX/lib/libfftw3f.so" \
    -DFFTW3f_THREADS_LIBRARIES="$FFTW_PREFIX/lib/libfftw3f_threads.so" \
    -DPYTHON_EXECUTABLE="$python" -DENABLE_DEFAULT=OFF -DENABLE_TESTING=OFF \
    -DENABLE_GNURADIO_RUNTIME=ON -DENABLE_GR_BLOCKS=ON -DENABLE_GR_ANALOG=ON \
    -DENABLE_GR_FFT=ON -DENABLE_GR_FILTER=ON -DENABLE_GR_DIGITAL=ON -DENABLE_GR_CHANNELS=ON \
    -DENABLE_PYTHON=OFF -DENABLE_GRC=OFF -DENABLE_GR_CTRLPORT=OFF \
    -DENABLE_CTRLPORT_THRIFT=OFF -DENABLE_EXAMPLES=OFF -DENABLE_COMMON_PCH=OFF \
    -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON -DENABLE_POSTINSTALL=OFF \
    -DENABLE_BASH_COMPLETIONS=OFF -DENABLE_ZSH_COMPLETIONS=OFF -DENABLE_FISH_COMPLETIONS=OFF \
    -DCMAKE_DISABLE_FIND_PACKAGE_SNDFILE=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_Doxygen=ON
if [ "${CONFIGURE_ONLY:-0}" = 1 ]; then
    echo "Configured in $work/gnuradio-build; GNU Radio is not built or installed."
    exit 0
fi
"$recipe/finish-build.sh" "$work"
