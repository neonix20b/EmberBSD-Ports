#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Own an isolated X11 desktop, D-Bus bus and configuration.
set -eu
umask 077
[ "$(uname -s)" = NetBSD ] || { echo 'Run on EmberBSD/NetBSD.' >&2; exit 2; }
[ "$#" -ge 3 ] && [ "$#" -le 4 ] || { echo 'Usage: sh run-nested.sh openbox|awesome|enlightenment|xfce PREFIX WORK [--headless]' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
desktop=$1
prefix=$2
work=$3
mode=${4:-nested}
case "$desktop" in openbox|awesome|enlightenment|xfce) ;; *) exit 2 ;; esac
case "$mode" in nested|--headless) ;; *) exit 2 ;; esac
case "$prefix" in /*) ;; *) exit 2 ;; esac
case "$prefix" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a path without shell metacharacters.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
helpers=$recipe/../enlightenment
[ -d "$work" ] || mkdir "$work"
PATH="$prefix/bin:$prefix/libexec:/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin"
LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
XDG_DATA_DIRS="$prefix/share:/usr/pkg/share:/usr/share"
XDG_CONFIG_DIRS="$prefix/etc/xdg:/usr/pkg/etc/xdg"
if [ "$desktop" = enlightenment ]; then
    : "${EFL_PREFIX:?Set EFL_PREFIX for Enlightenment}"
    case "$EFL_PREFIX" in /*) ;; *) exit 2 ;; esac
    case "$EFL_PREFIX" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
    PATH="$prefix/bin:$EFL_PREFIX/bin:$PATH"
    LD_LIBRARY_PATH="$prefix/lib:$EFL_PREFIX/lib:$LD_LIBRARY_PATH"
    XDG_DATA_DIRS="$prefix/share:$EFL_PREFIX/share:$XDG_DATA_DIRS"
fi
case "$desktop" in
    enlightenment) binary=enlightenment_start ;;
    xfce) binary=xfce4-session ;;
    *) binary=$desktop ;;
esac
if [ "$desktop" = awesome ]; then
    LUA_PATH="$prefix/share/lua/5.4/?.lua;$prefix/share/lua/5.4/?/init.lua;;"
    LUA_CPATH="$prefix/lib/lua/5.4/?.so;;"
    export LUA_PATH LUA_CPATH
fi
[ -x "$prefix/bin/$binary" ] || { echo "Missing $prefix/bin/$binary" >&2; exit 2; }
export XDG_DATA_DIRS XDG_CONFIG_DIRS
export PATH LD_LIBRARY_PATH
command -v timeout >/dev/null
number=${X11_DISPLAY_NUMBER:-82}
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
    if [ -n "$lock" ]; then
        rmdir "$lock" || cleanup_error=1
    fi
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
candidate=/tmp/emberbsd-x11-desktop-x$number.lock
mkdir "$candidate" || { echo 'Another probe holds this display.' >&2; exit 2; }
lock=$candidate
if [ -e "/tmp/.X11-unix/X$number" ] || [ -e "/tmp/.X$number-lock" ]; then
    echo "Display :$number is occupied; choose X11_DISPLAY_NUMBER." >&2
    exit 2
fi
cc -O2 -Wall -Wextra "$helpers/session-exec.c" -o "$session/session-exec"
cc -std=c99 -D_NETBSD_SOURCE -DMARKER='"EMBERBSD_X11_SESSION"' -O2 -Wall -Wextra -Werror \
    "$helpers/session-processes.c" -o "$session/session-processes"
unset EMBERBSD_X11_SESSION
if [ "$mode" = nested ]; then
    "$session/session-exec" Xephyr ":$number" -screen 1024x640 -nolisten tcp -no-host-grab \
        > "$session/xserver.log" 2>&1 < /dev/null &
else
    "$session/session-exec" Xvfb ":$number" -screen 0 1024x640x24 -nolisten tcp \
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
XDG_CONFIG_HOME=$session/config
XDG_CACHE_HOME=$session/cache
XDG_DATA_HOME=$session/data
XDG_RUNTIME_DIR=$session/runtime

XDG_CONFIG_DIRS="$prefix/etc/xdg:/usr/pkg/etc/xdg"
XDG_CURRENT_DESKTOP=$desktop
XDG_SESSION_DESKTOP=$desktop
XDG_SESSION_TYPE=x11
EMBERBSD_X11_SESSION=$session
E_COMP_ENGINE=sw
ELM_ENGINE=software_x11
GDK_BACKEND=x11
QT_QPA_PLATFORM=xcb
export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_RUNTIME_DIR
export XDG_DATA_DIRS XDG_CONFIG_DIRS XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
export EMBERBSD_X11_SESSION
scope_ready=true
export E_COMP_ENGINE ELM_ENGINE GDK_BACKEND QT_QPA_PLATFORM
unset E_WL_FORCE E_CONF_PROFILE WAYLAND_DISPLAY WAYLAND_SOCKET
unset E_HOME E_HOME_DIR E_START E_RESTART E_RESTART_OK
unset E_PREFIX E_BIN_DIR E_LIB_DIR E_DATA_DIR E_LOCALE_DIR
unset DBUS_SESSION_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE
unset SESSION_MANAGER
if [ "$desktop" = xfce ]; then
    XDG_CURRENT_DESKTOP=XFCE
    XDG_CONFIG_DIRS=$prefix/etc/xdg
    DBUS_SYSTEM_BUS_ADDRESS=unix:path=$session/runtime/no-system-bus
    export XDG_CURRENT_DESKTOP XDG_CONFIG_DIRS DBUS_SYSTEM_BUS_ADDRESS
    unset XDG_SEAT_PATH XDG_SESSION_PATH
    sh "$recipe/../xfce/prepare-session.sh" "$prefix" "$XDG_CONFIG_HOME"
fi
unset GTK_IM_MODULE GSK_RENDERER GDK_GL
E_HOME=$session/config/enlightenment
export E_HOME
EMBERBSD_X11_DESKTOP=$desktop
export EMBERBSD_X11_DESKTOP
ulimit -c 0
cat > "$session/start.sh" <<'START'
#!/bin/sh
set -eu
printf '%s\n' "$DBUS_SESSION_BUS_ADDRESS" > "$XDG_RUNTIME_DIR/bus-address"
case "$EMBERBSD_X11_DESKTOP" in
    openbox) exec openbox --sm-disable ;;
    awesome) exec awesome ;;
    enlightenment) exec enlightenment_start -profile standard ;;
    xfce) exec xfce4-session ;;
esac
START
chmod 700 "$session/start.sh"
printf '%s\n' "$DISPLAY" > "$session/display"
printf '%s\n' "$session" > "$work/last-session.txt"
printf 'X11 session: %s\nDisplay: %s\n' "$session" "$DISPLAY"
"$session/session-exec" dbus-run-session -- "$session/start.sh" > "$session/desktop.log" 2>&1 < /dev/null &
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
