#!/bin/sh
# Exercise real Qt Wayland drawing and input through a private nested KWin.
# SPDX-License-Identifier: MIT
set -eu
umask 077
recipe_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$recipe_dir/scripts/nested-lifecycle.sh"
build_root=${BUILD_ROOT:-"$HOME/.cache/emberbsd-plasma-kwin"}
case "$build_root" in /*) ;; *) echo 'BUILD_ROOT must be absolute.' >&2; exit 2 ;; esac
case "$build_root" in *[!a-zA-Z0-9_./-]*) echo 'Use a BUILD_ROOT without shell metacharacters.' >&2; exit 2 ;; esac
prefix=${PREFIX:-"$build_root/install"}
plasma_prefix=${PLASMA_PREFIX:?Set PLASMA_PREFIX to the matching Plasma installation}
input_prefix=${LIBINPUT_PREFIX:?Set LIBINPUT_PREFIX to the validated libopeninput installation}
display=${CONTRACT_DISPLAY:-:79}
number=${display#:}
case "$display" in :*) ;; *) echo 'Use CONTRACT_DISPLAY=:NUMBER.' >&2; exit 2 ;; esac
case "$number" in ''|*[!0-9]*) echo 'Display number must be numeric.' >&2; exit 2 ;; esac
[ "$number" -ge 1 ] && [ "$number" -le 65535 ] || exit 2
PATH="$prefix/bin:$plasma_prefix/bin:/usr/pkg/qt6/bin:/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin"
export PATH
export LD_LIBRARY_PATH="$prefix/lib:$plasma_prefix/lib:$input_prefix/lib:/usr/pkg/qt6/lib:/usr/pkg/lib:/usr/X11R7/lib"
export QT_PLUGIN_PATH="$prefix/lib/plugins:$plasma_prefix/lib/plugins:/usr/pkg/qt6/plugins"
export QML2_IMPORT_PATH="$prefix/lib/qml:$plasma_prefix/lib/qml:/usr/pkg/qt6/qml"
export XDG_DATA_DIRS="$prefix/share:$plasma_prefix/share:/usr/pkg/share:/usr/X11R7/share"
prepare_profile
echo "Evidence directory: $run"
export DISPLAY="$display" WAYLAND_DISPLAY=kwin-contract
socket_path=$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY
[ "$(LC_ALL=C printf '%s' "$socket_path" | wc -c | tr -d ' ')" -le 103 ] || {
    echo 'BUILD_ROOT is too long for a NetBSD Wayland socket.' >&2; exit 2
}
x_pid= kwin_pid= client_pid= bus_pid= display_guard=
contract_complete=false
x_socket=/tmp/.X11-unix/X$number
x_lock=/tmp/.X$number-lock
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
candidate=/tmp/emberbsd-plasma-x$number.lock
mkdir "$candidate" || { echo 'Another probe holds this display.' >&2; exit 2; }
display_guard=$candidate
if [ -e "$x_socket" ] || [ -L "$x_socket" ] || [ -e "$x_lock" ] || [ -L "$x_lock" ]; then
    echo "Display $display is occupied; choose CONTRACT_DISPLAY." >&2
    exit 2
fi
export LC_ALL=C.UTF-8 XCURSOR_THEME=Adwaita
export XCURSOR_PATH="$plasma_prefix/share/icons:/usr/pkg/share/icons:/usr/X11R7/lib/X11/icons"
export KWIN_COMPOSE=Q QT_QUICK_BACKEND=software KWIN_RENDER_NODES= KWIN_DISABLE_VULKAN=1 LIBGL_ALWAYS_SOFTWARE=1
export PKG_CONFIG_PATH=/usr/pkg/qt6/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/X11R7/lib/pkgconfig
/usr/bin/c++ -std=c++23 -O2 "$recipe_dir/scripts/wayland-client-probe.cpp" \
    $(pkg-config --cflags --libs Qt6Widgets) -Wl,--no-undefined -Wl,--fatal-warnings \
    -Wl,-rpath,/usr/pkg/qt6/lib -Wl,-rpath,/usr/pkg/lib \
    -o "$run/wayland-client"
/usr/bin/cc -O2 "$recipe_dir/scripts/x11-input-probe.c" \
    -I/usr/X11R7/include -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib -lX11 -lXtst \
    -Wl,--no-undefined -Wl,--fatal-warnings -o "$run/x11-input"
dbus-daemon --nofork --nosyslog --config-file="$run/bus.conf" --print-address=1 \
    >"$run/bus-address.txt" 2>"$run/dbus.log" &
bus_pid=$!
printf 'dbus=%s\n' "$bus_pid" >"$run/pids.txt"
i=0
until [ -s "$run/bus-address.txt" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; do
    kill -0 "$bus_pid"
    i=$((i + 1)); [ "$i" -lt 15 ] || exit 13
    sleep 1
done
kill -0 "$bus_pid"
DBUS_SESSION_BUS_ADDRESS=$(head -n 1 "$run/bus-address.txt")
export DBUS_SESSION_BUS_ADDRESS
Xvfb "$display" -screen 0 800x600x24 -nolisten tcp >"$run/xvfb.log" 2>&1 &
x_pid=$!
i=0
until xdpyinfo -display "$display" >"$run/xdpyinfo.txt" 2>&1; do
    kill -0 "$x_pid"
    i=$((i + 1)); [ "$i" -lt 15 ] || exit 10
    sleep 1
done
# Do not attach to an existing display if our X server could not start.
sleep 1
kill -0 "$x_pid"
[ -f "$x_lock" ] && [ "$(tr -d '[:space:]' <"$x_lock")" = "$x_pid" ] || {
    echo 'The ready X server does not belong to this probe.' >&2; exit 1
}
kwin_wayland --x11-display "$display" --socket "$WAYLAND_DISPLAY" \
    --width 800 --height 600 --no-global-shortcuts --no-kactivities >"$run/kwin.log" 2>&1 &
kwin_pid=$!
printf 'xvfb=%s\nkwin=%s\n' "$x_pid" "$kwin_pid" >>"$run/pids.txt"
i=0
until [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; do
    kill -0 "$kwin_pid"
    i=$((i + 1)); [ "$i" -lt 30 ] || exit 11
    sleep 1
done
sleep 2
qdbus org.kde.KWin /KWin org.kde.KWin.supportInformation >"$run/support-information.txt"
grep 'Compositing Type: QPainter' "$run/support-information.txt"
QT_QPA_PLATFORM=wayland "$run/wayland-client" "$run/input-receipt.txt" >"$run/client.log" 2>&1 &
client_pid=$!
printf 'client=%s\n' "$client_pid" >>"$run/pids.txt"
sleep 3
xwininfo -display "$display" -root -tree >"$run/x11-windows.txt"
"$run/x11-input" "$display"
i=0
until [ -s "$run/input-receipt.txt" ]; do
    kill -0 "$client_pid"
    i=$((i + 1)); [ "$i" -lt 20 ] || exit 12
    sleep 1
done
xwd -display "$display" -root -silent -out "$run/frame.xwd"
child_exited "$client_pid" 10 || { echo 'Wayland client did not exit.' >&2; exit 14; }
wait "$client_pid"
echo "reaped=client:$client_pid" >>"$run/cleanup.txt"
client_pid=
grep -qx 'platform=wayland' "$run/input-receipt.txt"
grep -qx 'text=emberbsd' "$run/input-receipt.txt"
kill -0 "$kwin_pid"
kill -0 "$bus_pid"
contract_complete=true
