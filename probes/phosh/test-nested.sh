#!/bin/sh
# Exercise the real private session and its process cleanup on an isolated Xvfb.
set -eu
umask 077
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
    echo 'Usage: sh test-nested.sh SHELL_BUILD_DIRECTORY OSK_PREFIX [GTK4_PREFIX]' >&2
    exit 2
}
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
work=$1
termination=${PHOSH_TEST_TERMINATION:-shell}
case "$termination" in shell|osk|stopped-osk) ;; *) echo 'Unknown PHOSH_TEST_TERMINATION.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
PATH=/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin
export PATH
log=$(mktemp -d "$work/check.XXXXXX")
xvfb=
runner=
shell_pid=
osk_pid=
cleanup()
{
    trap - EXIT HUP INT TERM
    for pid in "$shell_pid" "$osk_pid" "$runner" "$xvfb"; do
        [ -n "$pid" ] || continue
        kill "$pid" 2>/dev/null || true
    done
    # Failure cleanup must also handle a stopped child.
    sleep 1
    for pid in "$shell_pid" "$osk_pid" "$runner" "$xvfb"; do
        [ -n "$pid" ] || continue
        if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null || true; fi
    done
    [ -z "$runner" ] || wait "$runner" 2>/dev/null || true
    [ -z "$xvfb" ] || wait "$xvfb" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
Xvfb -displayfd 3 -screen 0 800x600x24 -nolisten tcp \
    3> "$log/display" > "$log/xvfb.log" 2>&1 < /dev/null &
xvfb=$!
i=0
while [ ! -s "$log/display" ]; do
    kill -0 "$xvfb"
    i=$((i + 1))
    [ "$i" -lt 15 ] || { echo 'Xvfb startup timed out.' >&2; exit 1; }
    sleep 1
done
DISPLAY=:$(cat "$log/display")
export DISPLAY
unset XAUTHORITY
sh "$recipe/run-nested.sh" "$@" > "$log/session.log" 2>&1 < /dev/null &
runner=$!
i=0
session=
while :; do
    session=$(sed -n 's/^Nested session: //p' "$log/session.log")
    [ -z "$session" ] || [ ! -s "$session/runtime/bus-address" ] || break
    kill -0 "$runner" || { cat "$log/session.log" >&2; exit 1; }
    i=$((i + 1))
    [ "$i" -lt 20 ] || { echo 'Session startup timed out.' >&2; exit 1; }
    sleep 1
done
DBUS_SESSION_BUS_ADDRESS=$(cat "$session/runtime/bus-address")
export DBUS_SESSION_BUS_ADDRESS
gdbus wait --session --timeout 20 org.gnome.Shell
gdbus wait --session --timeout 20 sm.puri.OSK0
bus_pid()
{
    gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.GetConnectionUnixProcessID "$1" |
        sed -n 's/^(uint32 \([0-9][0-9]*\),)$/\1/p'
}
shell_pid=$(bus_pid org.gnome.Shell)
osk_pid=$(bus_pid sm.puri.OSK0)
case "$shell_pid:$osk_pid" in *[!0-9:]*|:*|*:) echo 'Invalid service PIDs.' >&2; exit 1 ;; esac
kill -0 "$shell_pid"
kill -0 "$osk_pid"
support=$(cat "$work/support-prefix.txt")
PKG_CONFIG_PATH="$support/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
LD_LIBRARY_PATH="$support/lib:/usr/pkg/lib:/usr/X11R7/lib"
export PKG_CONFIG_PATH LD_LIBRARY_PATH
pkgconf() { sh "$recipe/native-pkg-config.sh" "$@"; }
cc $(pkgconf --cflags gtk+-3.0) "$recipe/gtk3/test-im-context.c" \
    -o "$log/test-im-context" $(pkgconf --libs gtk+-3.0)
XDG_RUNTIME_DIR=$session/runtime
WAYLAND_DISPLAY=emberbsd-phosh
GDK_BACKEND=wayland
GTK_IM_MODULE=wayland
export XDG_RUNTIME_DIR WAYLAND_DISPLAY GDK_BACKEND GTK_IM_MODULE
# A missing cache must reproduce the simple-context fallback, rather than
# making the positive check pass merely because GTK initialized.
status=0
GTK_IM_MODULE_FILE="$log/missing-cache" "$log/test-im-context" \
    > "$log/input-missing-cache.log" 2>&1 || status=$?
[ "$status" -eq 1 ] || { echo 'Missing-cache regression did not reproduce.' >&2; exit 1; }
"$log/test-im-context" > "$log/input-wayland.log" 2>&1
gdbus call --session --dest sm.puri.OSK0 --object-path /sm/puri/OSK0 \
    --method org.freedesktop.DBus.Properties.Get sm.puri.OSK0 Visible > "$log/osk-property.txt"
# Signal only children owned by this private bus. A stopped keyboard checks
# that cleanup has a deadline rather than waiting forever for SIGTERM.
case "$termination" in
    shell) kill -TERM "$shell_pid" ;;
    osk) kill -KILL "$osk_pid" ;;
    stopped-osk) kill -STOP "$osk_pid"; kill -TERM "$shell_pid" ;;
esac
i=0
while kill -0 "$runner" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -lt 15 ] || { echo 'Session cleanup timed out.' >&2; exit 1; }
    sleep 1
done
status=0
wait "$runner" || status=$?
runner=
if kill -0 "$osk_pid" 2>/dev/null; then
    echo 'On-screen keyboard survived the shell.' >&2
    exit 1
fi
if kill -0 "$shell_pid" 2>/dev/null; then
    echo 'Phosh survived session cleanup.' >&2
    exit 1
fi
case "$termination:$status" in
    shell:0|stopped-osk:0|osk:137) ;;
    *) echo "Unexpected exit status for $termination: $status" >&2; exit 1 ;;
esac
shell_pid=
osk_pid=
printf 'Private shell and OSK registered; %s cleanup passed (status %s). Logs: %s\n' "$termination" "$status" "$log"
