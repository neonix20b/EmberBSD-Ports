#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
umask 022
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: build.sh ABS_NEW_WORK [ABS_CACHE]' >&2; exit 2; }
work=$1
for directory in "$@"; do
    case "$directory" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$directory" in *[!a-zA-Z0-9_./-]*) echo 'Use simple paths.' >&2; exit 2 ;; esac
done
[ ! -e "$work" ] && [ ! -L "$work" ] || { echo 'Work path already exists.' >&2; exit 2; }
case "$(uname -s):$(uname -p)" in
    NetBSD:aarch64) ;;
    *) echo 'This baseline NEON profile requires native NetBSD/aarch64.' >&2; exit 2 ;;
esac
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || exit 2
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
cmake=${CMAKE:-cmake}
python=${PYTHON_EXECUTABLE:-python3}
for tool in "$cmake" ninja tar patch "$python"; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
if command -v sha256 >/dev/null; then
    digest() { sha256 -q "$1"; }
else
    command -v shasum >/dev/null || { echo 'sha256 or shasum required.' >&2; exit 2; }
    digest() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
fi
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
        tail -60 "$work/logs/$stage.log" >&2
        exit "$status"
    fi
}
# Verify every archive before extraction. All CMake network fallback is disabled.
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
while read -r name expected url; do
    tar -xf "$work/archives/$name" -C "$work/src"
done < "$recipe/sources.tsv"
{ uname -a; "$cmake" --version; ninja --version; "$python" --version; } > "$work/logs/tools.txt"
# Inspect existing generator dependencies through their upstream CLI. No pip install.
"$python" -m mako.cmd --help > "$work/logs/mako-cli.txt"
if command -v pkg_info >/dev/null; then
    pkg_info | grep -E '^(python|py[0-9]+-(mako|markupsafe))' >> "$work/logs/tools.txt"
fi
run fmt-header-patch patch -d "$work/src/volk-3.3.0" -p0 < "$recipe/patches/fmt-format-header.patch"
digest "$recipe/patches/fmt-format-header.patch" > "$work/logs/fmt-header-patch.sha256"
run netbsd-cxx-math-patch patch -d "$work/src/volk-3.3.0" -p0 < "$recipe/patches/netbsd-cxx-math.patch"
digest "$recipe/patches/netbsd-cxx-math.patch" > "$work/logs/netbsd-cxx-math-patch.sha256"
run fmt-configure "$cmake" -S "$work/src/fmt-12.2.0" -B "$work/fmt-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_RPATH="$prefix/lib" \
    -DBUILD_SHARED_LIBS=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DFMT_TEST=OFF -DFMT_DOC=OFF -DFMT_INSTALL=ON
run fmt-build "$cmake" --build "$work/fmt-build" --parallel "$jobs"
run fmt-install "$cmake" --install "$work/fmt-build"
run volk-configure "$cmake" -S "$work/src/volk-3.3.0" -B "$work/volk-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_RPATH="$prefix/lib" -DCMAKE_C_FLAGS=-march=armv8-a \
    -DCMAKE_CXX_FLAGS=-march=armv8-a -Dfmt_DIR="$prefix/lib/cmake/fmt" \
    -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
    -DVOLK_CPU_FEATURES=OFF -DCMAKE_DISABLE_FIND_PACKAGE_CpuFeatures=ON \
    -DENABLE_ORC=OFF -DENABLE_MODTOOL=OFF -DENABLE_TESTING=OFF \
    -DENABLE_PROFILING=OFF -DENABLE_STATIC_LIBS=OFF -DCMAKE_DISABLE_FIND_PACKAGE_Doxygen=ON \
    -DPYTHON_EXECUTABLE="$python"
# cpu_features lacks NetBSD/AArch64 detection; only baseline ARMv8 NEON is allowed.
grep -Fx -- '-- Available machines: generic;neon;neonv8' "$work/logs/volk-configure.log" >/dev/null || {
    echo 'Unexpected machine set; review baseline dispatch before building.' >&2; exit 1;
}
run volk-build "$cmake" --build "$work/volk-build" --parallel "$jobs"
run volk-install "$cmake" --install "$work/volk-build"
mkdir -p "$prefix/share/ember-volk/licenses"
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$prefix/share/ember-volk/"
cp "$work/src/volk-3.3.0/COPYING" "$prefix/share/ember-volk/licenses/VOLK-LGPL-3.0"
cp "$work/src/volk-3.3.0/cpu_features/LICENSE" "$prefix/share/ember-volk/licenses/cpu_features-Apache-2.0"
cp "$work/src/fmt-12.2.0/LICENSE" "$prefix/share/ember-volk/licenses/fmt-MIT"
echo "Installed in $prefix; run test.sh next."
