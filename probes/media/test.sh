#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: test.sh WORK' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple path without whitespace.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
videoio=${VIDEOIO:-OFF}
case "$videoio" in ON|OFF) ;; *) echo 'VIDEOIO must be ON or OFF.' >&2; exit 2 ;; esac
prefix=$work/install
PATH="$prefix/bin:$PATH"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
GST_PLUGIN_SYSTEM_PATH_1_0="$prefix/lib/gstreamer-1.0"
GST_PLUGIN_PATH_1_0=
GST_PLUGIN_PATH=
GST_PLUGIN_SYSTEM_PATH="$GST_PLUGIN_SYSTEM_PATH_1_0"
GST_PLUGIN_SCANNER="$prefix/libexec/gstreamer-1.0/gst-plugin-scanner"
GST_REGISTRY="$work/test-build/registry.bin"
export PATH PKG_CONFIG_PATH LD_LIBRARY_PATH GST_PLUGIN_SYSTEM_PATH_1_0 \
    GST_PLUGIN_PATH_1_0 GST_PLUGIN_PATH GST_PLUGIN_SYSTEM_PATH GST_PLUGIN_SCANNER GST_REGISTRY
cmake -S "$recipe/tests" -B "$work/test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_RPATH="$prefix/lib" \
    -DCMAKE_PREFIX_PATH="$prefix" -DVIDEOIO="$videoio"
cmake --build "$work/test-build" --parallel 1
ctest --test-dir "$work/test-build" --output-on-failure
for binary in "$work/test-build/ffmpeg-contract" "$work/test-build/gstreamer-contract"; do
    ldd "$binary"
done > "$work/logs/installed-linkage.txt"
if grep -q 'not found' "$work/logs/installed-linkage.txt"; then
    echo 'Missing runtime dependency.' >&2
    exit 1
fi
if grep -F '/usr/lib/libintl.so.1' "$work/logs/installed-linkage.txt" >/dev/null &&
    grep -F '/usr/pkg/lib/libintl.so.8' "$work/logs/installed-linkage.txt" >/dev/null; then
    echo 'Mixed base and pkgsrc libintl ABIs.' >&2; exit 1
fi
# Require selected libraries; finding another installed ABI is not acceptance.
for library in libavcodec libavformat libavutil libgstreamer-1.0 libgstapp-1.0; do
    grep -F "$prefix/lib/$library" "$work/logs/installed-linkage.txt" >/dev/null || {
        echo "Incorrect installed linkage: $library" >&2; exit 1;
    }
done
if [ "$videoio" = ON ]; then
    ldd "$work/test-build/videoio-contract" > "$work/logs/videoio-linkage.txt"
    if grep -q 'not found' "$work/logs/videoio-linkage.txt"; then
        echo 'Missing OpenCV runtime dependency.' >&2; exit 1
    fi
    if grep -F '/usr/lib/libintl.so.1' "$work/logs/videoio-linkage.txt" >/dev/null &&
        grep -F '/usr/pkg/lib/libintl.so.8' "$work/logs/videoio-linkage.txt" >/dev/null; then
        echo 'Mixed videoio libintl ABIs.' >&2; exit 1
    fi
    for library in libopencv_videoio libavcodec libgstreamer-1.0; do
        grep -F "$prefix/lib/$library" "$work/logs/videoio-linkage.txt" >/dev/null || {
            echo "Incorrect videoio linkage: $library" >&2; exit 1;
        }
    done
fi
