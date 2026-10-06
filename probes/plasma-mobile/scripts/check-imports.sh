#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Check real QML constructors in a disposable profile, without a compositor.
set -eu
[ "$(uname -s)" = NetBSD ] || { echo 'Run on EmberBSD/NetBSD.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
[ "$#" -eq 1 ] || { echo 'Usage: check-imports.sh WORK_DIRECTORY' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work directory.' >&2; exit 2 ;; esac
prefix=$work/install
[ -d "$prefix" ] || { echo 'Missing installation prefix.' >&2; exit 2; }
recipe=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
umask 077
session=$(mktemp -d "$work/import.XXXXXX")
mkdir "$session/config" "$session/cache" "$session/data" "$session/runtime"
export PATH="$prefix/bin:/usr/pkg/bin:/usr/pkg/qt6/bin:/usr/X11R7/bin:/usr/bin:/bin"
export LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/pkg/qt6/lib:/usr/X11R7/lib"
export QML_IMPORT_PATH="$prefix/lib/qt6/qml:/usr/pkg/qt6/qml"
export QT_PLUGIN_PATH="$prefix/lib/qt6/plugins:/usr/pkg/qt6/plugins"
export XDG_DATA_DIRS="$prefix/share:/usr/pkg/share:/usr/share"
export XDG_CONFIG_HOME="$session/config" XDG_CACHE_HOME="$session/cache"
export XDG_DATA_HOME="$session/data" XDG_RUNTIME_DIR="$session/runtime"
export XDG_CURRENT_DESKTOP=KDE PLASMA_PLATFORM=phone
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software LC_ALL=C.UTF-8 LD_BIND_NOW=1
export QT_QUICK_CONTROLS_STYLE=org.kde.breeze
unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET QML2_IMPORT_PATH
unset DBUS_SESSION_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE
unset QT_LOGGING_RULES QT_LOGGING_CONF QT_MESSAGE_PATTERN
status=0
dbus-run-session -- timeout --foreground -k 2 30 qml "$recipe/tests/ImportSmoke.qml" \
    > "$session/import.log" 2>&1 || status=$?
cat "$session/import.log"
[ "$status" -eq 0 ] || exit "$status"
# A partial Kirigami directory can hide its real controls while QML exits zero.
if grep -q 'qmlRegisterType requires absolute URLs' "$session/import.log"; then
    echo 'Kirigami selected an incomplete component directory.' >&2
    exit 1
fi
grep -q 'PASS: Plasma, Nano, battery, volume and Breeze QML constructors' "$session/import.log"
timeout --foreground -k 2 30 plasma-keyboard --version > "$session/keyboard-version.txt"
timeout --foreground -k 2 30 plasma-settings --version > "$session/settings-version.txt"
grep -Fx 'plasma-keyboard 6.7.5' "$session/keyboard-version.txt"
grep -Fx 'plasma-settings 26.08.1' "$session/settings-version.txt"
timeout --foreground -k 2 30 ldd "$prefix/bin/plasma-keyboard" > "$session/keyboard-ldd.txt"
if ! awk '
    /not found/ { missing = 1 }
    /stdc\+\+/ {
        runtimes++
        if ($1 == "-lstdc++.9" && $2 == "=>" && $3 == "/usr/lib/libstdc++.so.9") expected++
    }
    END { exit !(runtimes == 1 && expected == 1 && !missing) }
' "$session/keyboard-ldd.txt"; then
    echo 'Expected exactly one system libstdc++.so.9 and no unresolved dependencies.' >&2
    exit 1
fi
printf 'Import and constructor checks passed. Evidence: %s\n' "$session"
