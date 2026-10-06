#!/bin/sh
# SPDX-License-Identifier: MIT
# Source probe only; this is not a pkgsrc package installer.
set -eu
umask 022
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: build.sh NEW_WORK [ARCHIVE_DIRECTORY]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple path without whitespace.' >&2; exit 2 ;; esac
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || { echo 'JOBS must be positive.' >&2; exit 2; }
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
scons=${SCONS:-scons-3.13}
for tool in cc c++ cmake ninja "$scons" sha256 curl tar patch; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
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
        echo "Failed: $stage ($status)" >&2
        exit "$status"
    fi
}
# Verify every archive before extracting any source.
while read -r name expected url; do
    if [ "$#" = 2 ]; then
        cp "$2/$name" "$work/archives/$name"
    else
        curl -fLsS --connect-timeout 20 --max-time 900 "$url" -o "$work/archives/$name"
    fi
    actual=$(sha256 -q "$work/archives/$name")
    [ "$actual" = "$expected" ] || { echo "Checksum mismatch: $name" >&2; exit 2; }
    printf '%s %s %s\n' "$name" "$actual" "$url" >> "$work/logs/sources.txt"
done < "$recipe/sources.tsv"
for archive in "$work"/archives/*.tar.gz; do
    tar -xzf "$archive" -C "$work/src"
done
{
    uname -a
    cc --version
    cmake --version
    ninja --version
    "$scons" --version
} > "$work/logs/tools.txt"
run eigen-configure cmake -S "$work/src/eigen-5.0.1" -B "$work/eigen-build" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release \
    -DEIGEN_BUILD_TESTING=OFF -DEIGEN_BUILD_DOC=OFF -DEIGEN_BUILD_BLAS=OFF \
    -DEIGEN_BUILD_LAPACK=OFF -DEIGEN_BUILD_DEMOS=OFF
run eigen-install cmake --install "$work/eigen-build"
run opencv-patch patch -d "$work/src/opencv-5.0.0" -p1 < "$recipe/patches/opencv-netbsd-arm64.patch"
run opencv-configure cmake -S "$work/src/opencv-5.0.0" -B "$work/opencv-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_PREFIX_PATH="$prefix" -DBUILD_SHARED_LIBS=ON \
    -DBUILD_LIST=core,imgproc,imgcodecs,features,geometry,calib \
    -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF \
    -DBUILD_opencv_apps=OFF -DBUILD_JAVA=OFF -DBUILD_opencv_python3=OFF \
    -DWITH_EIGEN=ON -DWITH_LAPACK=OFF -DWITH_OPENCL=OFF -DWITH_IPP=OFF \
    -DWITH_ITT=OFF -DWITH_KLEIDICV=OFF -DWITH_CAROTENE=OFF \
    -DWITH_VULKAN=OFF -DWITH_CUDA=OFF -DWITH_PROTOBUF=OFF \
    -DWITH_FFMPEG=OFF -DWITH_GSTREAMER=OFF -DWITH_GTK=OFF -DWITH_QT=OFF \
    -DWITH_AVIF=OFF -DWITH_JPEG=OFF -DWITH_PNG=OFF -DWITH_TIFF=OFF \
    -DWITH_WEBP=OFF -DWITH_OPENEXR=OFF -DWITH_OPENJPEG=OFF -DWITH_JASPER=OFF \
    -DOPENCV_DOWNLOAD_TRIES_LIST= -DOPENCV_GENERATE_PKGCONFIG=ON
run opencv-build cmake --build "$work/opencv-build" --parallel "$jobs"
run opencv-install cmake --install "$work/opencv-build"
# Python runs upstream SCons; Python bindings and GUI clients are excluded.
cd "$work/src/gpsd-release-3.27.5"
run gpsd-build "$scons" -j "$jobs" prefix="$prefix" shared=yes python=no \
    qt=no xgps=no ncurses=no dbus_export=no shm_export=no bluez=no usb=no \
    systemd=no manbuild=no
run gpsd-check "$scons" -j 1 check
run gpsd-install "$scons" install
mkdir -p "$prefix/share/robotics-foundations/licenses/eigen"
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$prefix/share/robotics-foundations/"
cp -R "$recipe/patches" "$prefix/share/robotics-foundations/"
cp "$work/src/opencv-5.0.0/LICENSE" "$prefix/share/robotics-foundations/licenses/OpenCV-LICENSE"
cp "$work/src/eigen-5.0.1"/COPYING* "$prefix/share/robotics-foundations/licenses/eigen/"
cp "$work/src/gpsd-release-3.27.5/COPYING" "$prefix/share/robotics-foundations/licenses/gpsd-COPYING"
echo "Built and installed in $prefix; run test.sh to verify installed consumers."
