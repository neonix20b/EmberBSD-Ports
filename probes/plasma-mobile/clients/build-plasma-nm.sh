#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 EmberBSD contributors. AI-assisted portability probe.
set -eu
# This diagnostic cohort uses NetBSD base libstdc++.so.9.
export CC=/usr/bin/cc CXX=/usr/bin/c++
work=${WORK:-"$HOME/.cache/emberbsd-plasma-support"}
export PATH=/usr/pkg/qt6/bin:/usr/pkg/bin:/usr/bin:/bin
export PKG_CONFIG_PATH="$work/prefix/lib/pkgconfig:$work/prefix/share/pkgconfig:/usr/pkg/lib/pkgconfig"
export QML_IMPORT_PATH="$work/prefix/lib/qml:${PLASMA_PREFIX:?Set PLASMA_PREFIX to the current shared Plasma installation}/lib/qt6/qml:/usr/pkg/qt6/qml"
export LC_ALL=en_US.UTF-8
cd "$work"
qt-cmake -S src/plasma-nm-6.7.5 -B build-plasma-nm -G Ninja \
 -DCMAKE_C_COMPILER=/usr/bin/cc -DCMAKE_CXX_COMPILER=/usr/bin/c++ \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$work/prefix" \
 -DCMAKE_PREFIX_PATH="$work/prefix;${PLASMA_PREFIX:?Set PLASMA_PREFIX to the current shared Plasma installation};/usr/pkg/qt6;/usr/pkg" \
 -DCMAKE_SHARED_LINKER_FLAGS=-Wl,--no-fatal-warnings \
 -DCMAKE_MODULE_LINKER_FLAGS=-Wl,--no-fatal-warnings \
 -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF -DBUILD_TESTING=ON \
 -DPLASMANM_DBUS_CLIENT_ONLY=ON -DBUILD_OPENCONNECT=OFF \
 > logs/plasma-nm-configure.log 2>&1
cmake --build build-plasma-nm --parallel "${JOBS:-1}" > logs/plasma-nm-build.log 2>&1
cmake --install build-plasma-nm > logs/plasma-nm-install.log 2>&1
QT_QPA_PLATFORM=offscreen dbus-run-session -- ctest --test-dir build-plasma-nm \
 --output-on-failure --parallel 1 > logs/plasma-nm-test.log 2>&1
