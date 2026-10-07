#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted regression for the inherited pkgsrc Sun audio port.
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 PATCHED_FFMPEG_SOURCE NEW_WORK" >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || { echo 'Run on native NetBSD.' >&2; exit 2; }
source=$(CDPATH= cd -- "$1" && pwd)
mkdir "$2"
cd "$2"
# This bounded API check is not the package configuration or an audio device test.
"$source/configure" --cc="${CC:-cc}" --arch="$(uname -p)" --disable-debug --disable-everything --disable-autodetect \
    --disable-programs --disable-doc --disable-network --disable-asm \
    --enable-indev=sunau --enable-outdev=sunau > configure.log 2>&1
"${GMAKE:-gmake}" -j1 libavdevice/sunau.o libavdevice/sunau_dec.o \
    libavdevice/sunau_enc.o > compile.log 2>&1 || {
    cat compile.log >&2; exit 1;
}
grep -q '^#define CONFIG_SUNAU_INDEV 1$' config_components.h
grep -q '^#define CONFIG_SUNAU_OUTDEV 1$' config_components.h
grep -q 'ff_sunau_demuxer' libavdevice/indev_list.c
grep -q 'ff_sunau_muxer' libavdevice/outdev_list.c
echo 'PASS: native Sun audio objects and input/output registration; no device I/O claim'
