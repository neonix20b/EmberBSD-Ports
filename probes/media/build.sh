#!/bin/sh
# SPDX-License-Identifier: MIT
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
python=${PYTHON:-python3.13}
for tool in cc c++ gmake meson ninja pkg-config bison flex glib-mkenums "$python" sha256 curl tar readelf; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
mkdir "$work"
mkdir "$work/src" "$work/archives" "$work/logs" "$work/build-tools"
# pkgsrc installs versioned Python; upstream generators use env python3.
ln -s "$(command -v "$python")" "$work/build-tools/python3"
prefix=$work/install
# pkgsrc GLib uses base libintl, but its bare -lintl can select the pkgsrc ABI.
glib_pc=$(pkg-config --variable=pcfiledir glib-2.0)/glib-2.0.pc
glib_lib=$(pkg-config --variable=libdir glib-2.0)/libglib-2.0.so
if readelf -d "$glib_lib" | grep -F 'Shared library: [libintl.so.1]' >/dev/null; then
    [ -r /usr/lib/libintl.so.1 ] || { echo 'Missing GLib base libintl ABI.' >&2; exit 2; }
    mkdir -p "$prefix/lib/pkgconfig"
    sed 's@-lintl@/usr/lib/libintl.so.1@g' "$glib_pc" > "$prefix/lib/pkgconfig/glib-2.0.pc"
    sha256 "$glib_pc" > "$work/logs/glib-pkgconfig-origin.txt"
fi
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
for archive in "$work"/archives/*.tar.xz; do
    tar -xf "$archive" -C "$work/src"
done
{
    uname -a
    cc --version
    meson --version
    ninja --version
    "$python" --version
    pkg-config --modversion glib-2.0 gio-2.0
} > "$work/logs/tools.txt"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
PATH="$work/build-tools:$prefix/bin:$PATH"
export PKG_CONFIG_PATH LD_LIBRARY_PATH PATH
mkdir "$work/ffmpeg-build"
cd "$work/ffmpeg-build"
run ffmpeg-configure "$work/src/ffmpeg-9.0.2/configure" \
    --prefix="$prefix" --enable-shared --disable-static --enable-rpath --enable-pic \
    --disable-debug --disable-doc --disable-autodetect --disable-network \
    --disable-avdevice --disable-everything \
    --enable-encoder=ffv1,rawvideo,pcm_s16le \
    --enable-decoder=ffv1,rawvideo,pcm_s16le \
    --enable-muxer=matroska,avi,wav,rawvideo \
    --enable-demuxer=matroska,avi,wav,rawvideo \
    --enable-protocol=file,pipe --enable-filter=scale,format,aresample
run ffmpeg-build gmake -j "$jobs"
run ffmpeg-install gmake install
cd "$work"
# Upstream Meson and glib-mkenums use Python at build time.
run gstreamer-configure meson setup "$work/gstreamer-build" "$work/src/gstreamer-1.28.7" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    --auto-features=disabled -Dtools=enabled -Dgst_debug=true
run gstreamer-build ninja -C "$work/gstreamer-build" -j "$jobs"
run gstreamer-install ninja -C "$work/gstreamer-build" install
run gst-base-configure meson setup "$work/gst-base-build" "$work/src/gst-plugins-base-1.28.7" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    --auto-features=disabled -Dtools=enabled -Dapp=enabled -Drawparse=enabled \
    -Dvideoconvertscale=enabled -Dvideotestsrc=enabled -Daudioconvert=enabled \
    -Daudioresample=enabled -Daudiotestsrc=enabled
run gst-base-build ninja -C "$work/gst-base-build" -j "$jobs"
run gst-base-install ninja -C "$work/gst-base-build" install
mkdir -p "$prefix/share/ember-media/licenses"
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$prefix/share/ember-media/"
cp "$work/src/ffmpeg-9.0.2/COPYING.LGPLv2.1" "$prefix/share/ember-media/licenses/FFmpeg-LGPLv2.1"
cp "$work/src/ffmpeg-9.0.2/LICENSE.md" "$prefix/share/ember-media/licenses/FFmpeg-LICENSE.md"
cp "$work/src/gstreamer-1.28.7/COPYING" "$prefix/share/ember-media/licenses/GStreamer-COPYING"
cp "$work/src/gst-plugins-base-1.28.7/COPYING" "$prefix/share/ember-media/licenses/Gst-base-COPYING"
echo "Installed current media profile in $prefix; run test.sh next."
