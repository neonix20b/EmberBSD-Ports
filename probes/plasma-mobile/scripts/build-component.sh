#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted native Plasma build helper.
set -eu
[ "$(uname -s)" = NetBSD ] || { echo 'Run on EmberBSD/NetBSD.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
root=${PLASMA_BUILD_ROOT:-$HOME/.cache/emberbsd-plasma-current}
case "$root" in /*) ;; *) echo 'Use an absolute build root.' >&2; exit 2 ;; esac
prefix=$root/install
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
component=${1:?usage: build-component.sh SOURCE_DIRECTORY}
shift
case "$component" in ''|*[!a-zA-Z0-9._-]*) echo 'Invalid source directory name.' >&2; exit 2 ;; esac
case ${JOBS:-1} in 1|2) ;; *) echo 'JOBS must be 1 or 2.' >&2; exit 2 ;; esac
export LC_ALL=C.UTF-8
: "${CC:=/usr/bin/cc}"
: "${CXX:=/usr/bin/c++}"
export CC CXX
export PATH=/usr/pkg/bin:/usr/pkg/qt6/bin:/usr/X11R7/bin:/usr/bin:/bin
export PKG_CONFIG_PATH=$prefix/lib/pkgconfig:$prefix/share/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/X11R7/lib/pkgconfig
export LD_LIBRARY_PATH=$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib
export QML_IMPORT_PATH=$prefix/lib/qt6/qml:/usr/pkg/qt6/qml
mkdir -p "$root/logs" "$root/build" "$prefix"
cmake -S "$root/src/$component" -B "$root/build/$component" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_PREFIX_PATH="$prefix;/usr/pkg;/usr/pkg/qt6;/usr/X11R7" \
    -DCMAKE_PROJECT_INCLUDE="$recipe/prefer-current-prefix.cmake" \
    -DEMBERBSD_PLASMA_PREFIX="$prefix" \
    -DCMAKE_SHARED_LINKER_FLAGS=-Wl,--no-fatal-warnings \
    -DCMAKE_MODULE_LINKER_FLAGS=-Wl,--no-fatal-warnings \
    -DCMAKE_INSTALL_RPATH="$prefix/lib;/usr/pkg/lib;/usr/X11R7/lib" \
    -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF -DKDE_INSTALL_QMLDIR=lib/qt6/qml \
    -DKDE_INSTALL_PLUGINDIR=lib/qt6/plugins -DKF_IGNORE_PLATFORM_CHECK=ON \
    -DBUILD_TESTING=OFF -DBUILD_DOC=OFF "$@" \
    >"$root/logs/$component-configure.log" 2>&1 || { tail -60 "$root/logs/$component-configure.log"; exit 1; }
cmake --build "$root/build/$component" --parallel "${JOBS:-1}" >"$root/logs/$component-build.log" 2>&1 || { tail -60 "$root/logs/$component-build.log"; exit 1; }
cmake --install "$root/build/$component" >"$root/logs/$component-install.log" 2>&1 || { tail -60 "$root/logs/$component-install.log"; exit 1; }
echo "Installed $component"
