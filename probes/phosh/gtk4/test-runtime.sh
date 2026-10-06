#!/bin/sh
# Check real GTK4 painting and both demos on an isolated Xvfb/Phoc display.
set -eu
umask 077
[ "$#" -eq 3 ] || { echo 'Usage: sh test-runtime.sh GTK_PREFIX PHOC_PREFIX NEW_WORK_DIRECTORY' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
gtk=$1
phoc=$2
work=$3
for path in "$gtk" "$phoc" "$work"; do
    case "$path" in /*) ;; *) echo 'All paths must be absolute.' >&2; exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./-]*) echo 'Use paths without shell metacharacters.' >&2; exit 2 ;; esac
done
[ "$(LC_ALL=C printf '%s' "$work/runtime/gtk4-test" | wc -c | tr -d ' ')" -le 103 ] || {
    echo 'Test path exceeds the NetBSD Unix socket limit.' >&2
    exit 2
}
[ -x "$gtk/bin/gtk4-demo" ] && [ -x "$gtk/bin/gtk4-widget-factory" ]
[ -x "$phoc/bin/phoc" ]
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
PATH="$gtk/bin:$phoc/bin:/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin"
PKG_CONFIG_PATH="$gtk/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
LD_LIBRARY_PATH="$gtk/lib:$phoc/lib:/usr/pkg/lib:/usr/X11R7/lib"
export PATH PKG_CONFIG_PATH LD_LIBRARY_PATH
command -v Xvfb >/dev/null
command -v xdpyinfo >/dev/null
display_number=${GTK4_TEST_DISPLAY_NUMBER:-88}
case "$display_number" in ''|*[!0-9]*) echo 'GTK4_TEST_DISPLAY_NUMBER must be numeric.' >&2; exit 2 ;; esac
[ "$display_number" -ge 1 ] && [ "$display_number" -le 65535 ] || exit 2
mkdir "$work"
mkdir "$work/runtime" "$work/config" "$work/cache" "$work/data"
xvfb=
runner=
display_lock=
alive_groups()
{
    for pid in "$runner" "$xvfb"; do
        [ -n "$pid" ] || continue
        if kill -0 -- "-$pid" 2>/dev/null || kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}
signal_groups()
{
    for pid in "$runner" "$xvfb"; do
        [ -n "$pid" ] || continue
        # The direct PID also covers cancellation before setsid() completes.
        kill -s "$1" "$pid" 2>/dev/null || true
        kill -s "$1" -- "-$pid" 2>/dev/null || true
    done
}
cleanup()
{
    signal_groups TERM
    i=0
    while alive_groups && [ "$i" -lt 3 ]; do
        sleep 1
        i=$((i + 1))
    done
    signal_groups KILL
    i=0
    while alive_groups && [ "$i" -lt 3 ]; do
        sleep 1
        i=$((i + 1))
    done
    cleanup_status=0
    if alive_groups; then
        echo 'Test process cleanup exceeded its deadline.' >&2
        cleanup_status=1
    fi
    for pid in "$runner" "$xvfb"; do
        [ -n "$pid" ] || continue
        if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" 2>/dev/null || true; fi
    done
    rm -f "$work/session-exec" || cleanup_status=1
    if [ -n "$display_lock" ]; then rmdir "$display_lock" || cleanup_status=1; fi
    return "$cleanup_status"
}
finish()
{
    exit_status=$?
    trap - EXIT
    trap '' HUP INT TERM
    cleanup_status=0
    cleanup || cleanup_status=$?
    [ "$exit_status" -ne 0 ] || exit_status=$cleanup_status
    exit "$exit_status"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
lock_candidate=/tmp/emberbsd-gtk4-x$display_number.lock
if ! mkdir "$lock_candidate"; then
    echo "Another GTK4 test holds display :$display_number." >&2
    exit 2
fi
display_lock=$lock_candidate
if [ -e "/tmp/.X11-unix/X$display_number" ] || [ -e "/tmp/.X$display_number-lock" ]; then
    echo "X display :$display_number is occupied; select a free GTK4_TEST_DISPLAY_NUMBER." >&2
    exit 2
fi
# pkg-config output is deliberately split into compiler arguments.
cc -Wall -Wextra -O2 $(sh "$recipe/../native-pkg-config.sh" --cflags gtk4) \
    "$recipe/test-client.c" -o "$work/test-client" \
    $(sh "$recipe/../native-pkg-config.sh" --libs gtk4)
ldd "$work/test-client" > "$work/ldd.log"
grep -F "$gtk/lib/libgtk-4.so" "$work/ldd.log" >/dev/null
cc -Wall -Wextra -O2 "$recipe/session-exec.c" -o "$work/session-exec"
XDG_RUNTIME_DIR=$work/runtime
XDG_CONFIG_HOME=$work/config
XDG_CACHE_HOME=$work/cache
XDG_DATA_HOME=$work/data
XDG_DATA_DIRS="$gtk/share:$phoc/share:/usr/pkg/share:/usr/share"
GSETTINGS_BACKEND=keyfile
WLR_BACKENDS=x11
WLR_RENDERER=pixman
GDK_BACKEND=wayland
GSK_RENDERER=cairo
GDK_GL=disable
GTK4_TEST_WORK=$work
export XDG_RUNTIME_DIR XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_DATA_DIRS
export GSETTINGS_BACKEND WLR_BACKENDS WLR_RENDERER GDK_BACKEND GSK_RENDERER GDK_GL GTK4_TEST_WORK
unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET XAUTHORITY
unset DBUS_SESSION_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE
owns_display()
{
    kill -0 "$xvfb" 2>/dev/null || return 1
    [ -f "/tmp/.X$display_number-lock" ] || return 1
    lock_pid=$(tr -d '[:space:]' < "/tmp/.X$display_number-lock")
    [ "$lock_pid" = "$xvfb" ]
}
DISPLAY=:$display_number
export DISPLAY
printf '%s\n' "$display_number" > "$work/display"
"$work/session-exec" Xvfb "$DISPLAY" -screen 0 800x600x24 -nolisten tcp \
    > "$work/xvfb.log" 2>&1 < /dev/null &
xvfb=$!
printf '%s\n' "$xvfb" > "$work/xvfb.pid"
i=0
while ! xdpyinfo > "$work/xdpyinfo.log" 2>&1; do
    kill -0 "$xvfb"
    i=$((i + 1))
    [ "$i" -lt 10 ] || { echo 'Xvfb startup timed out.' >&2; exit 1; }
    sleep 1
done
owns_display || { echo 'The ready X display is not owned by this test.' >&2; exit 1; }
cat > "$work/phoc.ini" <<'CONFIG'
[core]
xwayland=false

[output:X11-1]
mode=360x540
scale=1
CONFIG
cat > "$work/client.sh" <<'CLIENT'
#!/bin/sh
set -eu
ulimit -c 0
unset DISPLAY
"$GTK4_TEST_WORK/test-client" > "$GTK4_TEST_WORK/client.log" 2>&1
grep '^PASS:' "$GTK4_TEST_WORK/client.log"
WAYLAND_DEBUG=1 gtk4-demo --autoquit > "$GTK4_TEST_WORK/demo.log" 2>&1
grep -q "wl_surface.*attach(wl_buffer" "$GTK4_TEST_WORK/demo.log"
printf '%s\n' 'PASS: GTK4 Demo exited normally after rendering'
WAYLAND_DEBUG=1 GTK_DEBUG_AUTO_QUIT=1 gtk4-widget-factory > "$GTK4_TEST_WORK/widget-factory.log" 2>&1
grep -q "wl_surface.*attach(wl_buffer" "$GTK4_TEST_WORK/widget-factory.log"
printf '%s\n' 'PASS: GTK4 Widget Factory exited normally after rendering'
CLIENT
chmod 700 "$work/client.sh"
status=0
owns_display || { echo 'The test X server stopped before Phoc startup.' >&2; exit 1; }
"$work/session-exec" dbus-run-session -- "$phoc/bin/phoc" --config "$work/phoc.ini" \
    --socket gtk4-test --no-xwayland --exec "$work/client.sh" \
    > "$work/runtime.log" 2>&1 < /dev/null &
runner=$!
printf '%s\n' "$runner" > "$work/runner.pid"
# A background wait lets signal traps run without waiting for the compositor.
wait "$runner" || status=$?
cat "$work/runtime.log"
[ "$status" -eq 0 ] || exit "$status"
grep -q '^PASS:' "$work/client.log"
grep -q '^PASS: GTK4 Widget Factory' "$work/runtime.log"
printf 'Runtime checks passed. Logs: %s\n' "$work"
