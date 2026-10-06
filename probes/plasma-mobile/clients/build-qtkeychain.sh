#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 EmberBSD contributors. AI-assisted portability probe.
set -eu
# This diagnostic cohort uses NetBSD base libstdc++.so.9.
export CC=/usr/bin/cc CXX=/usr/bin/c++
work=${WORK:-"$HOME/.cache/emberbsd-plasma-support"}
export PATH=/usr/pkg/qt6/bin:/usr/pkg/bin:/usr/bin:/bin
export LC_ALL=en_US.UTF-8
cd "$work"
qt-cmake -S src/qtkeychain-0.17.0 -B build-qtkeychain -G Ninja \
 -DCMAKE_C_COMPILER=/usr/bin/cc -DCMAKE_CXX_COMPILER=/usr/bin/c++ \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$work/prefix" \
 -DBUILD_TESTING=OFF -DBUILD_WITH_QT5=OFF -DBUILD_TEST_APPLICATION=OFF -DBUILD_QTQUICK_DEMO=OFF \
 > logs/qtkeychain-configure.log 2>&1
cmake --build build-qtkeychain --parallel "${JOBS:-1}" > logs/qtkeychain-build.log 2>&1
cmake --install build-qtkeychain > logs/qtkeychain-install.log 2>&1
