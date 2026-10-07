#!/bin/sh
# SPDX-License-Identifier: MIT
# A disposable native source probe, not a package or system installer.
set -eu
umask 022
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: build.sh ABS_NEW_WORK [ABS_ARCHIVE_CACHE]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple work path.' >&2; exit 2 ;; esac
[ ! -e "$work" ] && [ ! -L "$work" ] || { echo 'Work path already exists.' >&2; exit 2; }
if [ "$#" = 2 ]; then
    case "$2" in /*) ;; *) echo 'Use an absolute archive cache.' >&2; exit 2 ;; esac
    [ -d "$2" ] || { echo 'Archive cache is not a directory.' >&2; exit 2; }
fi
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || { echo 'JOBS must be positive.' >&2; exit 2; }
eigen_prefix=${EIGEN_PREFIX:-$work/install}
if [ "${EIGEN_PREFIX+x}" = x ]; then
    case "$EIGEN_PREFIX" in /*) ;; *) echo 'Use an absolute Eigen prefix.' >&2; exit 2 ;; esac
    case "$EIGEN_PREFIX" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple Eigen prefix.' >&2; exit 2 ;; esac
    [ -f "$EIGEN_PREFIX/share/eigen3/cmake/Eigen3Config.cmake" ] &&
        grep -F 'set(PACKAGE_VERSION "5.0.1")' "$EIGEN_PREFIX/share/eigen3/cmake/Eigen3ConfigVersion.cmake" >/dev/null || {
        echo 'Common Eigen 5.0.1 required.' >&2; exit 2;
    }
fi
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
mkdir "$work"
mkdir "$work/src" "$work/archives" "$work/logs"
prefix=$work/install
printf '%s\n' "$eigen_prefix" > "$work/logs/eigen-prefix.txt"
hash()
{
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1";
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
# Check all archives before extracting any, including cached archives.
while read -r name expected url; do
    # A shared Eigen prefix supplies its own pinned headers and metadata.
    if [ "${EIGEN_PREFIX+x}" = x ] && [ "$name" = eigen-5.0.1.tar.gz ]; then continue; fi
    if [ "$#" = 2 ]; then
        cp "$2/$name" "$work/archives/$name"
    else
        curl -fLsS --connect-timeout 20 --max-time 900 "$url" -o "$work/archives/$name"
    fi
    actual=$(hash "$work/archives/$name")
    [ "$actual" = "$expected" ] || { echo "Checksum mismatch: $name; nothing extracted." >&2; exit 2; }
    printf '%s %s %s\n' "$name" "$actual" "$url" >> "$work/logs/sources.txt"
done < "$recipe/sources.tsv"
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
CC=${CC:-/usr/bin/cc}
CXX=${CXX:-/usr/bin/c++}
for tool in "$CC" "$CXX" cmake ninja tar patch; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
export CC CXX
printf '%s\n' "$(command -v "$CXX")" > "$work/logs/cxx.txt"
for archive in "$work"/archives/*.tar.gz; do tar -xzf "$archive" -C "$work/src"; done
{
    uname -a
    "$CC" --version
    "$CXX" --version
    cmake --version
    ninja --version
} > "$work/logs/tools.txt"
run()
{
    stage=$1
    shift
    printf '%s\n' "$stage"
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        tail -60 "$work/logs/$stage.log" >&2
        echo "Failed: $stage ($status)" >&2
        exit "$status"
    fi
}
if [ "${EIGEN_PREFIX+x}" != x ]; then
run eigen-configure cmake -S "$work/src/eigen-5.0.1" -B "$work/eigen-build" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON \
    -DEIGEN_BUILD_TESTING=OFF -DEIGEN_BUILD_DOC=OFF -DEIGEN_BUILD_BLAS=OFF \
    -DEIGEN_BUILD_LAPACK=OFF -DEIGEN_BUILD_DEMOS=OFF
run eigen-install cmake --install "$work/eigen-build"
fi
run ceres-eigen5-patch patch -d "$work/src/ceres-solver-2.2.0" -p1 < "$recipe/patches/ceres-eigen5.patch"
run ceres-configure cmake -S "$work/src/ceres-solver-2.2.0" -B "$work/ceres-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_PREFIX_PATH="$prefix;$eigen_prefix" \
    -DEigen3_DIR="$eigen_prefix/share/eigen3/cmake" \
    -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF \
    -DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON -DEXPORT_BUILD_DIR=OFF \
    -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF \
    -DBUILD_BENCHMARKS=OFF -DBUILD_DOCUMENTATION=OFF \
    -DMINIGLOG=ON -DGFLAGS=OFF -DUSE_CUDA=OFF -DLAPACK=OFF \
    -DSUITESPARSE=OFF -DEIGENSPARSE=ON -DEIGENMETIS=OFF
run ceres-build cmake --build "$work/ceres-build" --parallel "$jobs"
run ceres-install cmake --install "$work/ceres-build"
licenses=$prefix/share/ceres-probe/licenses
mkdir -p "$licenses/eigen"
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$prefix/share/ceres-probe/"
cp -R "$recipe/patches" "$prefix/share/ceres-probe/"
cp "$work/src/ceres-solver-2.2.0/LICENSE" "$licenses/Ceres-LICENSE"
if [ "${EIGEN_PREFIX+x}" != x ]; then
    cp "$work/src/eigen-5.0.1"/COPYING* "$licenses/eigen/"
elif [ -d "$eigen_prefix/share/robotics-foundations/licenses/eigen" ]; then
    cp "$eigen_prefix/share/robotics-foundations/licenses/eigen/"COPYING* "$licenses/eigen/"
fi
cp "$work/logs/eigen-prefix.txt" "$prefix/share/ceres-probe/"
echo "Installed in $prefix; run test.sh to verify the installed consumers."
