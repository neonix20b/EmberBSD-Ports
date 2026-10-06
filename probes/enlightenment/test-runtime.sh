#!/bin/sh
# Check the real WM, EWMH transitions and normal session shutdown.
set -eu
umask 077
[ "$#" -eq 1 ] || { echo 'Usage: sh test-runtime.sh SHELL_WORK' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
efl=$(cat "$work/efl-prefix.txt")
prefix=$work/install
PATH="$prefix/bin:$efl/bin:/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin"
LD_LIBRARY_PATH="$prefix/lib:$efl/lib:/usr/pkg/lib:/usr/X11R7/lib"
export PATH LD_LIBRARY_PATH
result=$(mktemp -d "$work/contract.XXXXXX")
launcher=
client=
cleanup()
{
    cleanup_error=0
    if [ -n "$client" ]; then
        kill -KILL "$client" 2>/dev/null || true
        kill -KILL -- "-$client" 2>/dev/null || true
        count=0
        while kill -0 "$client" 2>/dev/null && [ "$count" -lt 2 ]; do
            sleep 1
            count=$((count + 1))
        done
        if kill -0 "$client" 2>/dev/null; then
            echo "Test client $client did not exit after KILL." >&2
            cleanup_error=1
        else
            wait "$client" 2>/dev/null || true
        fi
    fi
    if [ -n "$launcher" ]; then
        kill -TERM "$launcher" 2>/dev/null || true
        count=0
        while kill -0 "$launcher" 2>/dev/null && [ "$count" -lt 12 ]; do
            sleep 1
            count=$((count + 1))
        done
        if kill -0 "$launcher" 2>/dev/null; then
            echo 'Launcher did not clean up within twelve seconds.' >&2
            return 1
        fi
        wait "$launcher" 2>/dev/null || true
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
cc -O2 -Wall -Wextra -I/usr/X11R7/include "$recipe/tests/x11-contract.c" \
    -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib -lX11 -o "$result/x11-contract"
ENLIGHTENMENT_DISPLAY_NUMBER=${ENLIGHTENMENT_DISPLAY_NUMBER:-79}
export ENLIGHTENMENT_DISPLAY_NUMBER
sh "$recipe/run-nested.sh" "$work" --headless > "$result/launcher.log" 2>&1 &
launcher=$!
count=0
session=
while [ -z "$session" ] || [ ! -s "$session/runtime/bus-address" ]; do
    kill -0 "$launcher" || { cat "$result/launcher.log" >&2; exit 1; }
    count=$((count + 1))
    [ "$count" -lt 20 ] || { echo 'Session startup timed out.' >&2; exit 1; }
    sleep 1
    # This file is the output of our specific child, never a shared latest link.
    session=$(sed -n 's/^Enlightenment session: //p' "$result/launcher.log")
done
DISPLAY=$(cat "$session/display")
DBUS_SESSION_BUS_ADDRESS=$(cat "$session/runtime/bus-address")
export DISPLAY DBUS_SESSION_BUS_ADDRESS
"$session/session-exec" timeout --foreground -k 1 45 "$result/x11-contract" \
    > "$result/contract.log" 2>&1 &
client=$!
status=0
wait "$client" || status=$?
client=
if [ "$status" -ne 0 ]; then
    cat "$result/contract.log" >&2
    tail -30 "$session/enlightenment.log" >&2
    exit 1
fi
cat "$result/contract.log"
timeout --foreground -k 1 3 enlightenment_remote -exit > "$result/exit.log" 2>&1
count=0
while kill -0 "$launcher" 2>/dev/null; do
    count=$((count + 1))
    [ "$count" -lt 20 ] || { echo 'Normal WM exit timed out.' >&2; exit 1; }
    sleep 1
done
wait "$launcher"
launcher=
if timeout --foreground -s 9 2 xdpyinfo >/dev/null 2>&1; then
    echo 'The owned X server remained alive after session exit.' >&2
    exit 1
fi
printf 'PASS: WM exit completed and its X server stopped\nEvidence: %s\nSession: %s\n' "$result" "$session"
