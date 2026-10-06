#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 EmberBSD contributors. AI-assisted portability probe.
set -eu
# This diagnostic cohort uses NetBSD base libstdc++.so.9.
export CC=/usr/bin/cc CXX=/usr/bin/c++
work=${WORK:-"$HOME/.cache/emberbsd-plasma-support"}
export PATH=/usr/pkg/qt6/bin:/usr/pkg/bin:/usr/bin:/bin
export PKG_CONFIG_PATH="$work/prefix/lib/pkgconfig:/usr/pkg/lib/pkgconfig"
export LC_ALL=en_US.UTF-8
cd "$work"
/usr/pkg/qt6/bin/qt-cmake -S src/networkmanager-qt-6.26.0 -B build-nmqt -G Ninja \
 -DCMAKE_C_COMPILER=/usr/bin/cc -DCMAKE_CXX_COMPILER=/usr/bin/c++ \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$work/prefix" \
 -DCMAKE_SHARED_LINKER_FLAGS=-Wl,--no-fatal-warnings \
 -DCMAKE_MODULE_LINKER_FLAGS=-Wl,--no-fatal-warnings \
 -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF -DBUILD_TESTING=ON \
 -DKF_IGNORE_PLATFORM_CHECK=ON -DNETWORKMANAGERQT_HEADERS_ONLY=ON \
 > logs/nmqt-configure.log 2>&1
cmake --build build-nmqt --parallel "${JOBS:-1}" --target KF6NetworkManagerQt networkmanagerqtqml > logs/nmqt-library-build.log 2>&1
cmake --install build-nmqt > logs/nmqt-install.log 2>&1
[ "${CLIENT_LIBRARIES_ONLY:-0}" = 1 ] && exit 0
cmake --build build-nmqt --parallel "${JOBS:-1}" > logs/nmqt-build.log 2>&1
dbus-run-session -- ctest --test-dir build-nmqt --output-on-failure --parallel 1 > logs/nmqt-test.log 2>&1
