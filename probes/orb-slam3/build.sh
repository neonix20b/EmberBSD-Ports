#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
umask 022
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
    echo 'Usage: build.sh ABS_NEW_WORK ABS_COMMON_PREFIX [ABS_CACHE]' >&2; exit 2;
}
work=$1
common=$2
opencv=${OPENCV_PREFIX:-$common}
cache=${3:-}
for directory in "$@" "$opencv"; do
    case "$directory" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$directory" in *[!a-zA-Z0-9_./-]*) echo 'Use simple paths without whitespace.' >&2; exit 2 ;; esac
done
[ ! -e "$work" ] && [ ! -L "$work" ] || { echo 'Work path already exists.' >&2; exit 2; }
[ -f "$opencv/lib/cmake/opencv5/OpenCVConfig.cmake" ] &&
    [ -f "$common/share/eigen3/cmake/Eigen3Config.cmake" ] || {
    echo 'Selected OpenCV/Eigen installation is missing.' >&2; exit 2;
}
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || { echo 'JOBS must be positive.' >&2; exit 2; }
# Leave inherited resource limits unchanged unless the caller selects a limit.
if [ -n "${BUILD_DATA_KIB:-}" ]; then
    case "$BUILD_DATA_KIB" in 0|*[!0-9]*) echo 'BUILD_DATA_KIB must be positive.' >&2; exit 2 ;; esac
    ulimit -d "$BUILD_DATA_KIB"
fi
if [ -n "${BUILD_VM_KIB:-}" ]; then
    case "$BUILD_VM_KIB" in 0|*[!0-9]*) echo 'BUILD_VM_KIB must be positive.' >&2; exit 2 ;; esac
    ulimit -v "$BUILD_VM_KIB"
fi
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
for tool in cmake ninja tar patch; do command -v "$tool" >/dev/null; done
if command -v sha256 >/dev/null; then
    digest() { sha256 -q "$1"; }
else
    command -v shasum >/dev/null
    digest() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
fi
[ -n "$cache" ] || command -v curl >/dev/null
mkdir "$work"
mkdir "$work/src" "$work/logs"
if [ -z "$cache" ]; then cache=$work/archives; mkdir "$cache"; fi
while read -r name expected url; do
    if [ "$#" != 3 ]; then
        curl -fLsS --connect-timeout 20 --max-time 1800 "$url" -o "$cache/$name"
    fi
    actual=$(digest "$cache/$name")
    [ "$actual" = "$expected" ] || { echo "Checksum mismatch: $name" >&2; exit 2; }
    printf '%s %s %s\n' "$name" "$actual" "$url" >> "$work/logs/sources.txt"
done < "$recipe/sources.tsv"
# Exclude duplicate example/evaluation datasets while preserving original code,
# vocabulary, RGB-D configuration and authorship. The original archive is unchanged.
root=ORB_SLAM3-1.0-release
tar -xzf "$cache/ORB_SLAM3-1.0.tar.gz" -C "$work/src" \
    "$root/src" "$root/include" "$root/Thirdparty" "$root/Vocabulary" \
    "$root/Examples/RGB-D" "$root/LICENSE" "$root/Dependencies.md" \
    "$root/README.md" "$root/Changelog.md" "$root/CMakeLists.txt"
run()
{
    stage=$1; shift
    printf '%s\n' "$stage"
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then tail -80 "$work/logs/$stage.log" >&2; exit "$status"; fi
}
source=$work/src/$root
run adaptation patch -d "$source" -p1 < "$recipe/patches/headless-modern-dependencies.patch"
digest "$recipe/patches/headless-modern-dependencies.patch" > "$work/logs/patch.sha256"
tar -xzf "$source/Vocabulary/ORBvoc.txt.tar.gz" -C "$source/Vocabulary"
prefix=$work/install
{ uname -a; cmake --version; ninja --version; printf 'RLIMIT_DATA_KiB='; ulimit -d;
  printf 'RLIMIT_AS_KiB='; ulimit -v; } > "$work/logs/tools.txt"
run configure cmake -S "$recipe/cmake" -B "$work/orb-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS_RELEASE='-O2 -DNDEBUG' \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DORB_SOURCE="$source" \
    -DCOMMON_PREFIX="$common" -DOPENCV_PREFIX="$opencv" -DORB_SLAM3_HEADLESS=ON
run build cmake --build "$work/orb-build" --parallel "$jobs"
run install cmake --install "$work/orb-build"
mkdir -p "$prefix/share/orb-slam3/licenses"
cp "$source/LICENSE" "$prefix/share/orb-slam3/licenses/ORB-SLAM3-GPL-3.0"
cp "$source/Thirdparty/g2o/license-bsd.txt" "$prefix/share/orb-slam3/licenses/g2o-BSD"
cp "$source/Thirdparty/Sophus/LICENSE.txt" "$prefix/share/orb-slam3/licenses/Sophus-MIT"
cp "$cache/DBoW2-LICENSE.txt" "$cache/DLib-LICENSE.txt" "$prefix/share/orb-slam3/licenses/"
cp "$recipe/LICENSE" "$prefix/share/orb-slam3/licenses/EmberBSD-MIT"
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$source/Dependencies.md" "$prefix/share/orb-slam3/"
echo "Installed in $prefix; run test.sh with the same common prefix."
