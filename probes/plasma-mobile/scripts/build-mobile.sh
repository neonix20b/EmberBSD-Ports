#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted native Plasma Mobile build helper.
set -eu
[ "$(uname -s)" = NetBSD ] || { echo 'Run on EmberBSD/NetBSD.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
root=${PLASMA_BUILD_ROOT:-$HOME/.cache/emberbsd-plasma-current}
prefix=${PLASMA_PREFIX:-$root/install}
build=${MOBILE_BUILD_DIR:-$root/build/plasma-mobile-6.7.5}
kwin=${KWIN_PREFIX:?Set KWIN_PREFIX to the matching KWin installation}
workspace=${WORKSPACE_PREFIX:?Set WORKSPACE_PREFIX to the matching Workspace installation}
clients=${CLIENTS_PREFIX:?Set CLIENTS_PREFIX to the service-client installation}
input=${LIBINPUT_PREFIX:?Set LIBINPUT_PREFIX to the validated libopeninput installation}
for directory in "$root" "$prefix" "$build" "$kwin" "$workspace" "$clients" "$input"; do
    case "$directory" in /*) ;; *) echo 'Use absolute source/build/install paths.' >&2; exit 2 ;; esac
done
case ${JOBS:-1} in 1|2) ;; *) echo 'JOBS must be 1 or 2.' >&2; exit 2 ;; esac
case ${CONFIGURE_ONLY:-0} in 0|1) ;; *) echo 'CONFIGURE_ONLY must be 0 or 1.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
: "${CC:=/usr/bin/cc}"
: "${CXX:=/usr/bin/c++}"
export CC CXX LC_ALL=C.UTF-8
export PATH=/usr/pkg/qt6/bin:/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin
export PKG_CONFIG_PATH="$clients/lib/pkgconfig:$clients/share/pkgconfig:$prefix/lib/pkgconfig:$prefix/share/pkgconfig:$input/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/X11R7/lib/pkgconfig"
export LD_LIBRARY_PATH="$input/lib:$kwin/lib:$workspace/lib:$clients/lib:$prefix/lib:/usr/pkg/qt6/lib:/usr/pkg/lib:/usr/X11R7/lib"
export QML_IMPORT_PATH="$clients/lib/qml:$workspace/lib/qt6/qml:$prefix/lib/qt6/qml:/usr/pkg/qt6/qml"
mkdir -p "$build"
cmake -S "$root/src/plasma-mobile-6.7.5" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_PREFIX_PATH="$kwin;$workspace;$clients;$prefix;$input;/usr/pkg/qt6;/usr/pkg;/usr/X11R7" \
    -DCMAKE_PROJECT_INCLUDE="$recipe/prefer-current-prefix.cmake" \
    -DEMBERBSD_PLASMA_PREFIX="$prefix" \
    -DCMAKE_INSTALL_RPATH="$input/lib;$kwin/lib;$workspace/lib;$clients/lib;$prefix/lib;/usr/pkg/qt6/lib;/usr/pkg/lib;/usr/X11R7/lib" \
    -DCMAKE_SHARED_LINKER_FLAGS=-Wl,--no-fatal-warnings \
    -DCMAKE_MODULE_LINKER_FLAGS=-Wl,--no-fatal-warnings \
    -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF -DKDE_INSTALL_QMLDIR=lib/qt6/qml \
    -DKDE_INSTALL_PLUGINDIR=lib/qt6/plugins -DKDE_INSTALL_SYSCONFDIR=etc \
    -DKF_IGNORE_PLATFORM_CHECK=ON -DBUILD_TESTING=ON \
    -DBUILD_SCREEN_RECORDING=OFF -DBUILD_PRIVILEGED_HELPERS=OFF \
    -DINSTALL_SYSTEMD_SERVICE=OFF \
    >"$build/configure.log" 2>&1 || { tail -80 "$build/configure.log"; exit 1; }
if [ "${CONFIGURE_ONLY:-0}" = 1 ]; then
    echo "Configured Plasma Mobile; compilation and installation not requested: $build"
    exit 0
fi
cmake --build "$build" --parallel "${JOBS:-1}" >"$build/build.log" 2>&1 || { tail -80 "$build/build.log"; exit 1; }
cmake --install "$build" >"$build/install.log" 2>&1 || { tail -80 "$build/install.log"; exit 1; }
echo "Installed Plasma Mobile in $prefix; runtime verification is separate."
