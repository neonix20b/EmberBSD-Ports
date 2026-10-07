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
build_as=${BUILD_AS_KIB:-}
if [ "${BUILD_AS_KIB+x}" = x ]; then
    case "$build_as" in ''|0|*[!0-9]*) echo 'BUILD_AS_KIB must be positive.' >&2; exit 2 ;; esac
    [ "$build_as" -gt 0 ] 2>/dev/null || { echo 'BUILD_AS_KIB must be positive.' >&2; exit 2; }
fi
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
mkdir "$work"
mkdir "$work/src" "$work/archives" "$work/logs"
prefix=$work/install
hash()
{
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1";
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
# Check all archives before extracting any, including cached archives.
while read -r name expected url; do
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
# Optional user-selected soft limit; preserve the inherited hard limit.
if [ -n "$build_as" ]; then
    ulimit -S -v "$build_as" || { echo 'Could not set the requested address-space limit.' >&2; exit 2; }
    [ "$(ulimit -S -v)" = "$build_as" ] || {
        echo 'Requested address-space limit verification failed.' >&2; exit 2;
    }
fi
CC=${CC:-/usr/bin/cc}
CXX=${CXX:-/usr/bin/c++}
for tool in "$CC" "$CXX" cmake ninja tar patch; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
export CC CXX
printf '%s\n' "$(command -v "$CXX")" > "$work/logs/cxx.txt"
: "${EIGEN_PREFIX:?Set EIGEN_PREFIX to the common Eigen 5.0.1 installation}"
case "$EIGEN_PREFIX" in /*) ;; *) echo 'Use an absolute Eigen prefix.' >&2; exit 2 ;; esac
case "$EIGEN_PREFIX" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple Eigen prefix.' >&2; exit 2 ;; esac
[ -f "$EIGEN_PREFIX/share/eigen3/cmake/Eigen3Config.cmake" ] || {
    echo 'Common Eigen installation is missing.' >&2; exit 2;
}
grep -F 'set(PACKAGE_VERSION "5.0.1")' "$EIGEN_PREFIX/share/eigen3/cmake/Eigen3ConfigVersion.cmake" >/dev/null || {
    echo 'Common Eigen 5.0.1 required.' >&2; exit 2;
}
printf '%s\n' "$EIGEN_PREFIX" > "$work/logs/eigen-prefix.txt"
PKG_CONFIG_PATH=/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig
export PKG_CONFIG_PATH
for archive in "$work"/archives/*.tar.gz; do tar -xzf "$archive" -C "$work/src"; done
{
    uname -a
    printf 'BUILD_AS_KIB=%s\nJOBS=%s\n' "$(ulimit -v)" "$jobs"
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
[ -f /usr/pkg/lib/cmake/Boost-1.91.0/BoostConfig.cmake ] || {
    echo 'Common Boost 1.91.0 required.' >&2; exit 2;
}
command -v pkg-config >/dev/null
pkg-config --modversion liblz4 >> "$work/logs/tools.txt"
[ "$(pkg-config --modversion liblz4)" = 1.10.0 ] || {
    echo 'Common LZ4 1.10.0 required.' >&2; exit 2;
}
pcl=$work/src/pcl-3346843ea6b97697a1577293aa9cdf236b5c7ffb
flann=$work/src/flann-c50f296b0b27e14667d272b37acc63f949b305c4
run pcl-eigen5-patch patch -d "$pcl" -p1 < "$recipe/patches/pcl-eigen5.patch"
# Upstream FLANN 1.9.2 still declares CMake 2.6; CMake 4 needs this policy floor.
run flann-configure cmake -S "$flann" -B "$work/flann-build" -G Ninja \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DFLANN_LIB_INSTALL_DIR=lib \
    -DCMAKE_INSTALL_RPATH="$prefix/lib;/usr/pkg/lib" \
    -DCMAKE_PREFIX_PATH=/usr/pkg -DCMAKE_DISABLE_FIND_PACKAGE_HDF5=ON \
    -DBUILD_C_BINDINGS=OFF -DBUILD_PYTHON_BINDINGS=OFF -DBUILD_MATLAB_BINDINGS=OFF \
    -DBUILD_CUDA_LIB=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTS=OFF -DBUILD_DOC=OFF \
    -DUSE_OPENMP=OFF -DUSE_MPI=OFF
run flann-build cmake --build "$work/flann-build" --parallel "$jobs"
run flann-install cmake --install "$work/flann-build"
run pcl-configure cmake -S "$pcl" -B "$work/pcl-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=17 -DCMAKE_CUDA_STANDARD=17 \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_PREFIX_PATH="$prefix;$EIGEN_PREFIX;/usr/pkg" \
    -DCMAKE_INSTALL_RPATH="$prefix/lib;/usr/pkg/lib" \
    -DEigen3_DIR="$EIGEN_PREFIX/share/eigen3/cmake" \
    -DBoost_DIR=/usr/pkg/lib/cmake/Boost-1.91.0 \
    -Dflann_DIR="$prefix/lib/cmake/flann" -DPCL_FLANN_REQUIRED_TYPE=SHARED \
    -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF \
    -DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON -DPCL_SHARED_LIBS=ON \
    -DPCL_ONLY_CORE_POINT_TYPES=ON -DPCL_ENABLE_MARCHNATIVE=OFF \
    -DPCL_ENABLE_SSE=OFF -DPCL_ENABLE_AVX=OFF -DWITH_OPENMP=OFF \
    -DWITH_VTK=OFF -DWITH_QT=NO -DWITH_OPENGL=OFF -DWITH_GLEW=OFF \
    -DWITH_CUDA=OFF -DWITH_OPENNI=OFF -DWITH_OPENNI2=OFF -DWITH_LIBUSB=OFF \
    -DWITH_PCAP=OFF -DWITH_PNG=OFF -DWITH_QHULL=OFF \
    -DCMAKE_DISABLE_FIND_PACKAGE_nanoflann=ON \
    -DBUILD_common=ON -DBUILD_kdtree=ON -DBUILD_octree=ON -DBUILD_search=ON \
    -DBUILD_sample_consensus=ON -DBUILD_filters=ON -DBUILD_features=ON \
    -DBUILD_registration=ON -DBUILD_io=ON -DBUILD_2d=ON \
    -DBUILD_geometry=ON -DBUILD_keypoints=OFF -DBUILD_ml=ON \
    -DBUILD_outofcore=OFF -DBUILD_people=OFF -DBUILD_recognition=OFF \
    -DBUILD_segmentation=ON -DBUILD_stereo=OFF -DBUILD_surface=ON \
    -DBUILD_tracking=OFF -DBUILD_visualization=OFF -DBUILD_apps=OFF \
    -DBUILD_examples=OFF -DBUILD_global_tests=OFF -DBUILD_tools=OFF \
    -DBUILD_simulation=OFF -DBUILD_GPU=OFF -DBUILD_CUDA=OFF
run pcl-build cmake --build "$work/pcl-build" --parallel "$jobs"
run pcl-install cmake --install "$work/pcl-build"
licenses=$prefix/share/pcl-probe/licenses
mkdir -p "$licenses"
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$prefix/share/pcl-probe/"
cp -R "$recipe/patches" "$prefix/share/pcl-probe/"
cp "$pcl/LICENSE.txt" "$licenses/PCL-LICENSE.txt"
cp "$flann/COPYING" "$licenses/FLANN-COPYING"
echo "Installed in $prefix; run test.sh to verify the installed consumers."
