#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Own a disposable X server, D-Bus bus and Plasma Mobile profile.
set -eu
umask 077
[ "$(uname -s)" = NetBSD ] || { echo 'Run on EmberBSD/NetBSD.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: run-nested.sh WORK_DIRECTORY [--headless]' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
work=$1
mode=${2:-nested}
case "$mode" in nested|--headless) ;; *) exit 2 ;; esac
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a work path without shell metacharacters.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
: "${LIBINPUT_PREFIX:?Set LIBINPUT_PREFIX to the validated libopeninput installation}"
case "$LIBINPUT_PREFIX" in /*) ;; *) echo 'LIBINPUT_PREFIX must be absolute.' >&2; exit 2 ;; esac
[ -d "$LIBINPUT_PREFIX/lib" ] || { echo 'Missing input library prefix.' >&2; exit 2; }
PATH=/usr/pkg/bin:/usr/pkg/qt6/bin:/usr/X11R7/bin:/usr/bin:/bin
LD_LIBRARY_PATH=/usr/pkg/lib:/usr/pkg/qt6/lib:/usr/X11R7/lib
QML_IMPORT_PATH=/usr/pkg/qt6/qml
QT_PLUGIN_PATH=/usr/pkg/qt6/plugins
XDG_DATA_DIRS=/usr/pkg/share:/usr/share
XDG_CONFIG_DIRS=/usr/pkg/etc/xdg
# List one selected installation of each component, lowest priority first.
while IFS= read -r prefix; do
    case "$prefix" in ''|'#'*) continue ;; esac
    case "$prefix" in /*) ;; *) echo 'Prefix must be absolute.' >&2; exit 2 ;; esac
    [ -d "$prefix" ] || { echo "Missing prefix: $prefix" >&2; exit 2; }
    PATH="$prefix/bin:$prefix/libexec:$PATH"
    LD_LIBRARY_PATH="$prefix/lib:$LD_LIBRARY_PATH"
    QML_IMPORT_PATH="$prefix/lib/qt6/qml:$prefix/lib/qml:$QML_IMPORT_PATH"
    QT_PLUGIN_PATH="$prefix/lib/qt6/plugins:$prefix/lib/plugins:$QT_PLUGIN_PATH"
    XDG_DATA_DIRS="$prefix/share:$XDG_DATA_DIRS"
    XDG_CONFIG_DIRS="$prefix/etc/xdg:$XDG_CONFIG_DIRS"
done < "$work/prefixes.txt"
LD_LIBRARY_PATH="$LIBINPUT_PREFIX/lib:$LD_LIBRARY_PATH"
export PATH LD_LIBRARY_PATH QML_IMPORT_PATH QT_PLUGIN_PATH XDG_DATA_DIRS XDG_CONFIG_DIRS
export LD_BIND_NOW=1
for binary in kwin_wayland plasmashell plasma-keyboard plasma-mobile-envmanager dbus-run-session kwriteconfig6; do
    command -v "$binary" >/dev/null || { echo "Missing executable: $binary" >&2; exit 2; }
done
command -v timeout >/dev/null
number=${PLASMA_DISPLAY_NUMBER:-81}
case "$number" in ''|*[!0-9]*) echo 'Display number must be numeric.' >&2; exit 2 ;; esac
[ "$number" -ge 1 ] && [ "$number" -le 65535 ] || exit 2
if [ "$mode" = nested ]; then
    : "${DISPLAY:?Run from an X11 desktop, or choose --headless}"
    command -v Xephyr >/dev/null
else
    command -v Xvfb >/dev/null
fi
session=$(mktemp -d "$work/session.XXXXXX")
mkdir "$session/config" "$session/cache" "$session/data" "$session/runtime"
# CMake's link selection does not ensure that ld.elf_so selects the same
# libinput at runtime. Reject fallback to the incompatible packaged library.
timeout --foreground -k 2 30 ldd "$(command -v kwin_wayland)" > "$session/kwin-ldd.txt" 2>&1
if ! awk -v expected="$LIBINPUT_PREFIX/lib/libinput.so." \
    -f "$recipe/scripts/check-kwin-loader.awk" "$session/kwin-ldd.txt"; then
    echo "Unexpected input/C++ runtime or missing library; inspect $session/kwin-ldd.txt" >&2
    exit 1
fi
server=
runner=
lock=
scope_ready=false
cleanup()
{
    cleanup_error=0
    for sig in TERM KILL; do
        if [ "$scope_ready" = true ]; then
            scope_status=0
            "$session/session-processes" --signal "$sig" > "$session/cleanup-$sig.pids" || scope_status=$?
            [ "$scope_status" -ne 2 ] || cleanup_error=1
        fi
        for pid in "$runner" "$server"; do
            [ -n "$pid" ] || continue
            kill -s "$sig" "$pid" 2>/dev/null || true
            kill -s "$sig" -- "-$pid" 2>/dev/null || true
        done
        [ "$sig" = TERM ] || break
        count=0
        while [ "$count" -lt 3 ]; do
            alive=false
            for pid in "$runner" "$server"; do
                [ -n "$pid" ] || continue
                if kill -0 "$pid" 2>/dev/null || kill -0 -- "-$pid" 2>/dev/null; then alive=true; fi
            done
            [ "$alive" = true ] || break
            sleep 1
            count=$((count + 1))
        done
    done
    for pid in "$runner" "$server"; do
        [ -n "$pid" ] || continue
        count=0
        while kill -0 "$pid" 2>/dev/null && [ "$count" -lt 2 ]; do
            sleep 1
            count=$((count + 1))
        done
        if kill -0 "$pid" 2>/dev/null; then
            echo "Owned child $pid did not exit after KILL." >&2
            cleanup_error=1
        else
            wait "$pid" 2>/dev/null || true
        fi
    done
    if [ "$scope_ready" = true ]; then
        count=0
        while :; do
            scope_status=0
            "$session/session-processes" --check > "$session/remaining.pids" || scope_status=$?
            [ "$scope_status" -ne 1 ] || break
            count=$((count + 1))
            if [ "$scope_status" -eq 2 ] || [ "$count" -ge 3 ]; then
                echo 'Session process cleanup could not be confirmed.' >&2
                cleanup_error=1
                break
            fi
            "$session/session-processes" --signal KILL > "$session/cleanup-late.pids" || true
            sleep 1
        done
    fi
    # A killed X server cannot remove its own socket/lock. Only remove nodes
    # when the lock still identifies our now-exited direct child.
    if [ -n "$server" ] && ! kill -0 "$server" 2>/dev/null &&
       [ -f "/tmp/.X$number-lock" ] &&
       [ "$(tr -d '[:space:]' < "/tmp/.X$number-lock")" = "$server" ]; then
        rm -f "/tmp/.X11-unix/X$number" "/tmp/.X$number-lock" || cleanup_error=1
    fi
    [ -z "$lock" ] || rmdir "$lock"
    return "$cleanup_error"
}
finish()
{
    status=$?
    trap - EXIT
    trap '' HUP INT TERM
    cleanup || { [ "$status" -ne 0 ] || status=1; }
    exit "$status"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
candidate=/tmp/emberbsd-plasma-x$number.lock
mkdir "$candidate" || { echo 'Another probe holds this display.' >&2; exit 2; }
lock=$candidate
if [ -e "/tmp/.X11-unix/X$number" ] || [ -e "/tmp/.X$number-lock" ]; then
    echo "Display :$number is occupied; choose PLASMA_DISPLAY_NUMBER." >&2
    exit 2
fi
cc -O2 -Wall -Wextra "$recipe/../enlightenment/session-exec.c" -o "$session/session-exec"
cc -std=c99 -D_NETBSD_SOURCE -O2 -Wall -Wextra -Werror \
    '-DMARKER="EMBERBSD_PLASMA_SESSION"' "$recipe/../enlightenment/session-processes.c" -o "$session/session-processes"
unset EMBERBSD_PLASMA_SESSION
if [ "$mode" = nested ]; then
    "$session/session-exec" Xephyr ":$number" -screen 480x800 -nolisten tcp -no-host-grab \
        > "$session/xserver.log" 2>&1 < /dev/null &
else
    "$session/session-exec" Xvfb ":$number" -screen 0 480x800x24 -nolisten tcp \
        > "$session/xserver.log" 2>&1 < /dev/null &
fi
server=$!
printf '%s\n' "$server" > "$session/xserver.pid"
DISPLAY=:$number
export DISPLAY
unset XAUTHORITY
count=0
while ! timeout --foreground -s 9 2 xdpyinfo > "$session/xdpyinfo.log" 2>&1; do
    kill -0 "$server"
    count=$((count + 1))
    [ "$count" -lt 15 ] || { echo 'X server startup timed out.' >&2; exit 1; }
    sleep 1
done
kill -0 "$server"
[ "$(tr -d '[:space:]' < "/tmp/.X$number-lock")" = "$server" ] || {
    echo 'The ready X server does not belong to this launcher.' >&2; exit 1
}
# Keep the account HOME intact; all desktop state goes to this private profile.
XDG_CONFIG_HOME=$session/config
XDG_CACHE_HOME=$session/cache
XDG_DATA_HOME=$session/data
XDG_RUNTIME_DIR=$session/runtime
XDG_CURRENT_DESKTOP=KDE
XDG_SESSION_DESKTOP=plasma-mobile
XDG_SESSION_TYPE=wayland
EMBERBSD_PLASMA_SESSION=$session
export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_RUNTIME_DIR
export XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE EMBERBSD_PLASMA_SESSION
# Match upstream startplasmamobile while keeping its generated defaults private.
XDG_CONFIG_DIRS="$XDG_CONFIG_HOME/plasma-mobile:$XDG_CONFIG_DIRS"
export XDG_CONFIG_DIRS
socket_path=$XDG_RUNTIME_DIR/emberbsd-plasma
[ "$(LC_ALL=C printf '%s' "$socket_path" | wc -c | tr -d ' ')" -le 103 ] || {
    echo 'Work path is too long for a NetBSD Wayland socket.' >&2; exit 2
}
scope_ready=true
unset WAYLAND_DISPLAY WAYLAND_SOCKET DBUS_SESSION_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE
unset GTK_IM_MODULE QT_IM_MODULE
export LC_ALL=C.UTF-8 LIBGL_ALWAYS_SOFTWARE=1
export KWIN_RENDER_NODES= KWIN_DISABLE_VULKAN=1 KWIN_IM_SHOW_ALWAYS=1
export KWIN_COMPOSE=${PLASMA_COMPOSITOR:-O2}
export PLASMA_PLATFORM=phone:handset QT_QUICK_CONTROLS_MOBILE=true
export QT_QPA_PLATFORMTHEME=KDE QT_QUICK_CONTROLS_STYLE=org.kde.breeze
export QT_ENABLE_GLYPH_CACHE_WORKAROUND=1 PLASMA_INTEGRATION_USE_PORTAL=1
export PLASMA_DEFAULT_SHELL=org.kde.plasma.mobileshell
case "$KWIN_COMPOSE" in Q) export QT_QUICK_BACKEND=software ;; O2) unset QT_QUICK_BACKEND ;; *) echo 'Choose O2 or Q.' >&2; exit 2 ;; esac
ulimit -c 0
ulimit -n 8192
cat > "$session/start-shell.sh" <<'SHELL'
#!/bin/sh
set -eu
unset DISPLAY
export QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland EGL_PLATFORM=wayland
printf '%s\n' "$DBUS_SESSION_BUS_ADDRESS" > "$XDG_RUNTIME_DIR/bus-address"
printf '%s\n' "$WAYLAND_DISPLAY" > "$XDG_RUNTIME_DIR/wayland-display"
dbus-update-activation-environment --verbose QT_QPA_PLATFORM GDK_BACKEND WAYLAND_DISPLAY \
    XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
exec plasmashell --no-respawn --shell-plugin org.kde.plasma.mobileshell
SHELL
cat > "$session/start-compositor.sh" <<'SHELL'
#!/bin/sh
set -eu
# The envmanager sends reload signals; it must run inside our private bus.
QT_QPA_PLATFORM=offscreen plasma-mobile-envmanager --apply-settings
kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardEnabled true
exec kwin_wayland --x11-display "$DISPLAY" \
    --width 480 --height 800 --socket emberbsd-plasma \
    --inputmethod "$(command -v plasma-keyboard)" \
    --exit-with-session "$EMBERBSD_PLASMA_SESSION/start-shell.sh"
SHELL
chmod 700 "$session/start-shell.sh" "$session/start-compositor.sh"
printf '%s\n' "$DISPLAY" > "$session/display"
printf '%s\n' "$session" > "$work/last-session.txt"
printf 'Plasma Mobile session: %s\nDisplay: %s\n' "$session" "$DISPLAY"
"$session/session-exec" dbus-run-session -- "$session/start-compositor.sh" \
    > "$session/plasma.log" 2>&1 < /dev/null &
runner=$!
printf '%s\n' "$runner" > "$session/runner.pid"
status=0
while kill -0 "$runner" 2>/dev/null; do
    if ! kill -0 "$server" 2>/dev/null; then
        echo 'The owned X server exited unexpectedly.' >&2
        exit 1
    fi
    sleep 1
done
wait "$runner" || status=$?
exit "$status"
