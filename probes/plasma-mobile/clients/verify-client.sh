#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 EmberBSD contributors. AI-assisted contract probe.
set -eu
umask 077
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 1; }
work=${WORK:?Set WORK to the completed client library build directory}
plasma_prefix=${PLASMA_PREFIX:?Set PLASMA_PREFIX to the shared Plasma installation}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
prefix="$work/prefix"
probe_root=$(mktemp -d "$work/client-verification.XXXXXXXX")
log_dir="$probe_root/logs"
build_dir="$probe_root/build"
mkdir "$probe_root/config" "$probe_root/data" "$probe_root/cache" "$probe_root/run" "$log_dir"
printf 'Client verification logs: %s\n' "$log_dir"
export XDG_CONFIG_HOME="$probe_root/config" XDG_DATA_HOME="$probe_root/data" XDG_CACHE_HOME="$probe_root/cache"
export XDG_RUNTIME_DIR="$probe_root/run"
export XDG_DATA_DIRS="$prefix/share:$plasma_prefix/share:/usr/pkg/share:/usr/share"
export PATH=/usr/pkg/qt6/bin:/usr/pkg/bin:/usr/bin:/bin
export CC=/usr/bin/cc CXX=/usr/bin/c++
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS CMAKE_TOOLCHAIN_FILE
export LD_LIBRARY_PATH="$prefix/lib:$plasma_prefix/lib:/usr/pkg/qt6/lib:/usr/pkg/lib:/usr/X11R7/lib"
export LD_BIND_NOW=1
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/share/pkgconfig:/usr/pkg/qt6/lib/pkgconfig:/usr/pkg/lib/pkgconfig"
export QML_IMPORT_PATH="$prefix/lib/qml:$plasma_prefix/lib/qt6/qml:/usr/pkg/qt6/qml"
export QT_PLUGIN_PATH="$prefix/lib/qt6/plugins:$plasma_prefix/lib/qt6/plugins:/usr/pkg/qt6/plugins"
export LC_ALL=en_US.UTF-8 XDG_CURRENT_DESKTOP=KDE
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET QML2_IMPORT_PATH
unset DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID DBUS_SESSION_BUS_WINDOWID
unset DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE DBUS_SYSTEM_BUS_ADDRESS
unset QT_LOGGING_RULES QT_LOGGING_CONF QT_MESSAGE_PATTERN PLASMA_SESSION_GUI_TEST
command -v timeout >/dev/null
{
    uname -a
    "$CXX" --version
    cmake --version
    pkg-config --modversion Qt6Core networkmanager-headers
} > "$log_dir/client-environment.log" 2>&1
/bin/sh "$script_dir/tests/test-netbsd-ldd.sh" > "$log_dir/ldd-parser-test.log" 2>&1
timeout -k 2 120 qt-cmake -S "$script_dir/tests" -B "$build_dir" -G Ninja \
    -DCMAKE_CXX_COMPILER=/usr/bin/c++ -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$prefix;/usr/pkg/qt6;/usr/pkg" > "$log_dir/client-configure.log" 2>&1
timeout -k 2 120 cmake --build "$build_dir" --parallel 1 > "$log_dir/client-build.log" 2>&1
timeout -k 2 30 /usr/bin/cc -Werror=undef -I"$work/src/bluez-qt-6.26.0/src" \
    -I"$prefix/include/KF6/BluezQt" -I"$prefix/include/KF6/BluezQt/bluezqt" \
    "$script_dir/tests/a2dp-layout.c" -o "$build_dir/a2dp-layout" > "$log_dir/a2dp-build.log" 2>&1
check_abi() {
    artifact=$1
    output="$log_dir/ldd-$(basename "$artifact").log"
    timeout -k 2 30 ldd "$artifact" > "$output" 2>&1
    if ! awk -f "$script_dir/tests/check-netbsd-ldd.awk" "$output"; then
        echo "Expected exactly one base libstdc++.so.9 and no missing libraries: $artifact; inspect $output" >&2
        exit 1
    fi
}
# Include transitive closures for each separately loaded QML plugin and library.
for artifact in "$build_dir/client-probe" "$build_dir/qml-client-probe" \
    "$prefix/lib/libKF6ModemManagerQt.so.6.26.0" \
    "$prefix/lib/libKF6NetworkManagerQt.so.6.26.0" \
    "$prefix/lib/libKF6BluezQt.so.6.26.0" \
    "$prefix/lib/libqt6keychain.so.0.17.0" \
    "$prefix/lib/libplasmanm_internal.so" "$prefix/lib/libplasmanm_editor.so" "$prefix/lib/libplasmanm_cellular.so" \
    "$prefix/lib/qml/org/kde/networkmanager/libnetworkmanagerqtqml.so" \
    "$prefix/lib/qml/org/kde/bluezqt/libbluezqtextensionplugin.so" \
    "$prefix/lib/qml/org/kde/plasma/networkmanagement/libplasmanm_internalplugin.so" \
    "$prefix/lib/qml/org/kde/plasma/networkmanagement/cellular/libplasmanm_cellularplugin.so"; do
    check_abi "$artifact"
done
printf '%s\n' 'Client ABI checks passed: 13 ELF objects' > "$log_dir/client-abi-test.log"
timeout -k 2 30 "$build_dir/a2dp-layout" > "$log_dir/a2dp-test.log" 2>&1
grep -Fx 'A2DP SBC wire layout passed.' "$log_dir/a2dp-test.log" >/dev/null
timeout -k 2 30 dbus-run-session -- "$build_dir/client-probe" > "$log_dir/client-test.log" 2>&1
grep -Fx 'System D-Bus preflight passed: no owned or activatable client services.' "$log_dir/client-test.log" >/dev/null
grep -Fx 'Real Qt D-Bus clients: no service owners, no devices; clock conversion passed.' "$log_dir/client-test.log" >/dev/null
grep -E '^QtKeychain backend available: (true|false)$' "$log_dir/client-test.log" >/dev/null
for library in "$prefix/lib/libKF6NetworkManagerQt.so.6.26.0" "$prefix/lib/libKF6ModemManagerQt.so.6.26.0" "$prefix/lib/libplasmanm_internal.so" "$prefix/lib/libplasmanm_editor.so" "$prefix/lib/libplasmanm_cellular.so"; do
    objdump -p "$library"
done > "$log_dir/client-dynamic.log"
if grep -E 'NEEDED[[:space:]]+libnm\.' "$log_dir/client-dynamic.log"; then
    echo 'Unexpected libnm runtime dependency in headers-only build.' >&2
    exit 1
fi
for library in "$prefix/lib/libKF6NetworkManagerQt.so.6.26.0" "$prefix/lib/libplasmanm_internal.so" "$prefix/lib/libplasmanm_editor.so" "$prefix/lib/libplasmanm_cellular.so"; do
    nm -D --undefined-only "$library"
done > "$log_dir/client-undefined.log"
if grep -E '[[:space:]]nm_[[:alnum:]_]+(@|$)' "$log_dir/client-undefined.log"; then
    echo 'Unresolved libnm function found.' >&2
    exit 1
fi
# This step is reached only after the native probe passes; it repeats the preflight.
timeout -k 2 30 dbus-run-session -- "$build_dir/qml-client-probe" > "$log_dir/qml-client-test.log" 2>&1
grep -Fx 'System D-Bus preflight passed: no owned or activatable client services.' "$log_dir/qml-client-test.log" >/dev/null
for module in org.kde.networkmanager org.kde.bluezqt org.kde.plasma.networkmanagement org.kde.plasma.networkmanagement.cellular; do
    grep -Fx "Loaded real QML module: $module" "$log_dir/qml-client-test.log" >/dev/null
done
if grep -F 'qmlRegisterType requires absolute URLs' "$log_dir/client-test.log" "$log_dir/qml-client-test.log"; then
    echo 'Invalid QML type registration detected' >&2
    exit 1
fi
/bin/sh "$script_dir/tests/test-service-preflight.sh" "$build_dir/client-probe" "$build_dir/qml-client-probe" "$probe_root/preflight-tests" > "$log_dir/service-preflight-test.log" 2>&1
sha256 "$prefix/lib/libKF6ModemManagerQt.so.6.26.0" \
    "$prefix/lib/libKF6NetworkManagerQt.so.6.26.0" \
    "$prefix/lib/libKF6BluezQt.so.6.26.0" \
    "$prefix/lib/libqt6keychain.so.0.17.0" \
    "$prefix/lib/libplasmanm_internal.so" \
    "$prefix/lib/libplasmanm_editor.so" \
    "$prefix/lib/libplasmanm_cellular.so" > "$log_dir/client-artifact-sha256.log"
cat "$log_dir/ldd-parser-test.log" "$log_dir/client-abi-test.log" "$log_dir/client-test.log" \
    "$log_dir/qml-client-test.log" "$log_dir/a2dp-test.log" "$log_dir/service-preflight-test.log"
echo 'Client verification passed'
