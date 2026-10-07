#!/bin/sh
# Check the real WM, EWMH transitions and normal session shutdown.
set -eu
umask 077
[ "$(uname -s)" = NetBSD ] || { echo 'Run on EmberBSD/NetBSD.' >&2; exit 2; }
[ "$#" -eq 3 ] || { echo 'Usage: sh test-runtime.sh DESKTOP PREFIX WORK' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
desktop=$1
prefix=$2
work=$3
case "$desktop" in openbox|awesome|enlightenment|xfce) ;; *) exit 2 ;; esac
if [ "$desktop" = xfce ]; then
    # GUI assertions use the upstream English window titles.
    LC_ALL=C
    export LC_ALL
fi
for path in "$work" "$prefix"; do
    case "$path" in /*) ;; *) exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
done
[ -d "$work" ] || mkdir "$work"
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
efl=${EFL_PREFIX:-/usr/pkg}
PATH="$prefix/bin:$efl/bin:/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin"
LD_LIBRARY_PATH="$prefix/lib:$efl/lib:/usr/pkg/lib:/usr/X11R7/lib"
export PATH LD_LIBRARY_PATH
result=$(mktemp -d "$work/contract.XXXXXX")
launcher=
client=
owned_display=false
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
    if [ "$status" -ne 0 ] && [ "$owned_display" = true ]; then
        timeout --foreground -k 1 5 xwininfo -root -tree > "$result/failure-windows.txt" 2>&1 || true
        timeout --foreground -k 1 5 xprop -root _NET_ACTIVE_WINDOW > "$result/failure-focus.txt" 2>&1 || true
        timeout --foreground -k 1 5 xwd -root -silent -out "$result/failure-screen.xwd" 2>/dev/null || true
    fi
    cleanup || { [ "$status" -ne 0 ] || status=1; }
    exit "$status"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
cc -O2 -Wall -Wextra -I/usr/X11R7/include "$recipe/../enlightenment/tests/x11-contract.c" \
    -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib -lX11 -o "$result/x11-contract"
X11_DISPLAY_NUMBER=${X11_DISPLAY_NUMBER:-83}
export X11_DISPLAY_NUMBER
sh "$recipe/run-nested.sh" "$desktop" "$prefix" "$work" --headless > "$result/launcher.log" 2>&1 &
launcher=$!
count=0
session=
while [ -z "$session" ] || [ ! -s "$session/runtime/bus-address" ]; do
    kill -0 "$launcher" || { cat "$result/launcher.log" >&2; exit 1; }
    count=$((count + 1))
    [ "$count" -lt 20 ] || { echo 'Session startup timed out.' >&2; exit 1; }
    sleep 1
    # This file is the output of our specific child, never a shared latest link.
    session=$(sed -n 's/^X11 session: //p' "$result/launcher.log")
done
DISPLAY=$(cat "$session/display")
DBUS_SESSION_BUS_ADDRESS=$(cat "$session/runtime/bus-address")
export DISPLAY DBUS_SESSION_BUS_ADDRESS
owned_display=true
XDG_CONFIG_HOME=$session/config
XDG_CACHE_HOME=$session/cache
XDG_DATA_HOME=$session/data
XDG_RUNTIME_DIR=$session/runtime
XDG_DATA_DIRS="$prefix/share:$efl/share:/usr/pkg/share:/usr/share"
export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_RUNTIME_DIR XDG_DATA_DIRS
# The controller must outlive the session's cleanup. Only applications belong
# to its process scope; tagging the controller would kill its wait/sleep calls.
unset EMBERBSD_X11_SESSION
unset SESSION_MANAGER
case "$desktop" in
    openbox) expected=Openbox ;;
    awesome) expected=awesome ;;
    enlightenment) expected=Enlightenment ;;
    xfce) expected=Xfwm4 ;;
esac
"$session/session-exec" timeout --foreground -k 1 45 "$result/x11-contract" "$expected" \
    > "$result/contract.log" 2>&1 &
client=$!
status=0
wait "$client" || status=$?
client=
if [ "$status" -ne 0 ]; then
    cat "$result/contract.log" >&2
    tail -30 "$session/desktop.log" >&2
    exit 1
fi
cat "$result/contract.log"
cc -O2 -Wall -Wextra -Werror -I/usr/X11R7/include "$recipe/x11-input.c" \
    -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib -lX11 -lXtst -o "$result/x11-input"
# Use actual terminal and editor applications; input is delivered by XTEST.
env EMBERBSD_X11_SESSION="$session" xterm -T EmberBSD-editor -geometry 80x20+20+60 -e /usr/bin/vi "$result/edited.txt" > "$result/editor.log" 2>&1 &
env EMBERBSD_X11_SESSION="$session" xterm -T EmberBSD-terminal -geometry 60x12+550+60 > "$result/terminal.log" 2>&1 &
input()
{
    timeout --foreground -k 1 20 "$result/x11-input" "$@"
}
# Both newly mapped clients can initially request focus. Wait for both
# before typing, otherwise the second can steal the first one's input.
input EmberBSD-terminal focus
input EmberBSD-editor focus
text="EmberBSD $desktop keyboard and saved file"
input EmberBSD-editor text "i$text"
input EmberBSD-editor key Escape
input EmberBSD-editor text ':w'
input EmberBSD-editor key Return
input EmberBSD-terminal text "printf 'second window works\n' > $result/terminal.txt"
input EmberBSD-terminal key Return
count=0
while [ ! -s "$result/edited.txt" ] || [ ! -s "$result/terminal.txt" ]; do
    count=$((count + 1))
    [ "$count" -lt 10 ] || { echo 'Saved text did not appear.' >&2; exit 1; }
    sleep 1
done
printf '%s\n' "$text" > "$result/expected.txt"
printf 'second window works\n' > "$result/terminal-expected.txt"
cmp "$result/expected.txt" "$result/edited.txt"
cmp "$result/terminal-expected.txt" "$result/terminal.txt"
echo 'PASS: focus switched between two real applications; XTEST input saved exact text'
if [ "$desktop" = xfce ]; then
    sh "$recipe/../xfce/tests/check-applications.sh" "$prefix" "$result" "$session" \
        > "$result/xfce-applications.log" 2>&1 || {
        cat "$result/xfce-applications.log" >&2
        exit 1
    }
    cat "$result/xfce-applications.log"
fi
timeout --foreground -k 1 5 xwininfo -root -tree > "$result/windows.txt"
timeout --foreground -k 1 5 xwd -root -silent -out "$result/screen.xwd"
input EmberBSD-editor text ':q'
input EmberBSD-editor key Return
input EmberBSD-terminal text exit
input EmberBSD-terminal key Return
case "$desktop" in
    openbox) timeout --foreground -k 1 5 openbox --exit ;;
    awesome) timeout --foreground -k 1 5 awesome-client 'awesome.quit()' ;;
    enlightenment) timeout --foreground -k 1 5 enlightenment_remote -exit ;;
    xfce) timeout --foreground -k 1 5 xfce4-session-logout --logout --fast ;;
esac > "$result/exit.log" 2>&1
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
