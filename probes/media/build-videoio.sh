#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: build-videoio.sh MEDIA_WORK [OPENCV_ARCHIVE]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple path without whitespace.' >&2; exit 2 ;; esac
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || { echo 'JOBS must be positive.' >&2; exit 2; }
build_as=${BUILD_AS_KIB:-}
if [ "${BUILD_AS_KIB+x}" = x ]; then
    case "$build_as" in ''|0|*[!0-9]*) echo 'BUILD_AS_KIB must be positive.' >&2; exit 2 ;; esac
    [ "$build_as" -gt 0 ] 2>/dev/null || { echo 'BUILD_AS_KIB must be positive.' >&2; exit 2; }
fi
if [ -n "$build_as" ]; then
    ulimit -S -v "$build_as" || exit 2
    [ "$(ulimit -S -v)" = "$build_as" ] || exit 2
fi
: "${EIGEN_PREFIX:?Set the common Eigen 5.0.1 installation prefix}"
case "$EIGEN_PREFIX" in /*) ;; *) echo 'Use an absolute Eigen prefix.' >&2; exit 2 ;; esac
grep -F 'set(PACKAGE_VERSION "5.0.1")' "$EIGEN_PREFIX/share/eigen3/cmake/Eigen3ConfigVersion.cmake" >/dev/null || {
    echo 'Common Eigen 5.0.1 required.' >&2; exit 2;
}
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
prefix=$work/install
pkg-config --exists libpng libjpeg || {
    echo 'Existing system PNG and JPEG development libraries are required.' >&2; exit 2;
}
{
    printf 'libpng='; pkg-config --modversion libpng
    printf 'libjpeg='; pkg-config --modversion libjpeg
    pkg-config --variable=prefix libpng
    pkg-config --variable=prefix libjpeg
} > "$work/logs/opencv-codec-dependencies.txt"
[ ! -e "$work/videoio-build" ] && [ ! -e "$work/src/opencv-5.0.0" ] || {
    echo 'Preserve existing OpenCV work and use a fresh media work directory.' >&2; exit 2;
}
printf 'BUILD_AS_KIB=%s\nJOBS=%s\nEIGEN_PREFIX=%s\n' "$build_as" "$jobs" "$EIGEN_PREFIX" > "$work/logs/opencv-resources.txt"
# Media acceptance is a prerequisite for enabling the next layer.
sh "$recipe/test.sh" "$work"
mkdir "$work/videoio-build"
archive=$work/archives/opencv-5.0.0.tar.gz
if [ "$#" = 2 ]; then
    cp "$2" "$archive"
else
    curl -fLsS --connect-timeout 20 --max-time 900 \
        https://github.com/opencv/opencv/archive/refs/tags/5.0.0.tar.gz -o "$archive"
fi
[ "$(sha256 -q "$archive")" = b0528f5a1d379d59d4701cb28c36e22214cc51cf64594e5b56f2d3e6c0233095 ] || {
    echo 'OpenCV archive checksum mismatch.' >&2; exit 2;
}
printf '%s\n' 'opencv-5.0.0.tar.gz b0528f5a1d379d59d4701cb28c36e22214cc51cf64594e5b56f2d3e6c0233095 https://github.com/opencv/opencv/archive/refs/tags/5.0.0.tar.gz' \
    >> "$work/logs/sources.txt"
[ "$(sha256 -q "$recipe/patches/opencv-ffmpeg9-upstream.patch")" = \
    13bfd0f570e79d3dccd9652439a5413235cf0fffe74a87951f439ba45c039ad6 ] || {
    echo 'OpenCV upstream patch checksum mismatch.' >&2; exit 2;
}
tar -xzf "$archive" -C "$work/src"
run()
{
    stage=$1
    shift
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        tail -60 "$work/logs/$stage.log" >&2
        exit "$status"
    fi
}
run opencv-baseline-patch patch -d "$work/src/opencv-5.0.0" -p1 \
    < "$recipe/../robotics-foundations/patches/opencv-netbsd-arm64.patch"
run opencv-ffmpeg9-patch patch -d "$work/src/opencv-5.0.0" -p1 \
    < "$recipe/patches/opencv-ffmpeg9-upstream.patch"
run opencv-filesystem-patch patch -d "$work/src/opencv-5.0.0" -p1 \
    < "$recipe/patches/opencv-netbsd-filesystem.patch"
PATH="$prefix/bin:$PATH"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig:/usr/pkg/lib/pkgconfig"
LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH PKG_CONFIG_PATH LD_LIBRARY_PATH
run opencv-configure cmake -S "$work/src/opencv-5.0.0" -B "$work/videoio-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_PREFIX_PATH="$prefix;$EIGEN_PREFIX;/usr/pkg" -DBUILD_SHARED_LIBS=ON \
    -DEigen3_DIR="$EIGEN_PREFIX/share/eigen3/cmake" \
    -DCMAKE_INSTALL_RPATH="$prefix/lib;/usr/pkg/lib" \
    -DBUILD_LIST=core,imgproc,imgcodecs,features,geometry,stereo,calib,video,stitching,photo,videoio \
    -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF \
    -DBUILD_opencv_apps=OFF -DBUILD_JAVA=OFF -DBUILD_opencv_python3=OFF \
    -DWITH_EIGEN=ON -DWITH_LAPACK=OFF -DWITH_OPENCL=OFF -DWITH_IPP=OFF \
    -DWITH_ITT=OFF -DWITH_KLEIDICV=OFF -DWITH_CAROTENE=OFF \
    -DWITH_VULKAN=OFF -DWITH_CUDA=OFF -DWITH_PROTOBUF=OFF \
    -DWITH_FFMPEG=ON -DWITH_GSTREAMER=ON -DWITH_V4L=OFF -DWITH_GTK=OFF -DWITH_QT=OFF \
    -DWITH_AVIF=OFF -DWITH_JPEG=ON -DBUILD_JPEG=OFF -DWITH_PNG=ON -DBUILD_PNG=OFF -DWITH_TIFF=OFF \
    -DJPEG_INCLUDE_DIR=/usr/pkg/include -DJPEG_LIBRARY_RELEASE=/usr/pkg/lib/libjpeg.so \
    -DPNG_PNG_INCLUDE_DIR=/usr/pkg/include -DPNG_LIBRARY_RELEASE=/usr/pkg/lib/libpng16.so \
    -DWITH_WEBP=OFF -DWITH_OPENEXR=OFF -DWITH_OPENJPEG=OFF -DWITH_JASPER=OFF \
    -DOPENCV_DOWNLOAD_TRIES_LIST= -DOPENCV_GENERATE_PKGCONFIG=ON
run opencv-build cmake --build "$work/videoio-build" --parallel "$jobs"
run opencv-install cmake --install "$work/videoio-build"
mkdir -p "$prefix/share/ember-media/patches"
cp "$work/src/opencv-5.0.0/LICENSE" "$prefix/share/ember-media/licenses/OpenCV-LICENSE"
cp "$recipe/patches/"*.patch \
    "$recipe/../robotics-foundations/patches/opencv-netbsd-arm64.patch" \
    "$prefix/share/ember-media/patches/"
printf '%s\n' 'Shared OpenCV installed; run VIDEOIO=ON sh probes/media/test.sh WORK and the affected robotics consumers.'
