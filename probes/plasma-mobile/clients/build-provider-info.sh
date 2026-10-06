#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 EmberBSD contributors. AI-assisted portability probe.
set -eu
# This diagnostic cohort uses NetBSD base libstdc++.so.9.
export CC=/usr/bin/cc CXX=/usr/bin/c++
work=${WORK:-"$HOME/.cache/emberbsd-plasma-support"}
export PATH=/usr/pkg/bin:/usr/bin:/bin
cd "$work"
if [ -d build-provider-info ]; then
    meson setup --reconfigure build-provider-info src/mobile-broadband-provider-info-20251101 \
        --prefix="$work/prefix" > logs/provider-info-configure.log 2>&1
else
    meson setup build-provider-info src/mobile-broadband-provider-info-20251101 \
        --prefix="$work/prefix" > logs/provider-info-configure.log 2>&1
fi
meson compile -C build-provider-info -j "${JOBS:-1}" > logs/provider-info-build.log 2>&1
meson test -C build-provider-info --num-processes 1 --print-errorlogs > logs/provider-info-test.log 2>&1
meson install -C build-provider-info > logs/provider-info-install.log 2>&1
mkdir -p "$work/prefix/share/licenses/mobile-broadband-provider-info"
cp src/mobile-broadband-provider-info-20251101/COPYING "$work/prefix/share/licenses/mobile-broadband-provider-info/"
