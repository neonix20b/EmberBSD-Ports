#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Exercise cancellation of the real GUI launcher on dedicated display :80 only.
set -eu
umask 077
[ "$#" -eq 2 ] || { echo 'Usage: test-launcher-cancellation.sh RECIPE SHELL_WORK' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user' >&2; exit 2; }
recipe=$(CDPATH= cd -- "$1" && pwd)
work=$(CDPATH= cd -- "$2" && pwd)
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Unsupported work path' >&2; exit 2 ;; esac
for path in /tmp/.X11-unix/X80 /tmp/.X80-lock /tmp/emberbsd-enlightenment-x80.lock; do
    [ ! -e "$path" ] || { echo "Display :80 already has state: $path" >&2; exit 2; }
done
result=$(mktemp -d "$work/cancellation.XXXXXX")
launcher= server= session= sentinel= blocked=
old_latest=false
if [ -f "$work/last-session.txt" ]; then
    cp "$work/last-session.txt" "$result/last-session.before"
    old_latest=true
fi
PATH=/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin
export PATH
unset EMBERBSD_ENLIGHTENMENT_SESSION

server_owned()
{
    [ -n "$server" ] && [ -f /tmp/.X80-lock ] &&
        [ "$(tr -d '[:space:]' < /tmp/.X80-lock)" = "$server" ] &&
        ps -p "$server" -o args= | grep -Eq '(^|/)Xvfb :80 '
}
reap_if_gone()
{
    reap_pid=$1
    reap_count=0
    while kill -0 "$reap_pid" 2>/dev/null && [ "$reap_count" -lt 20 ]; do
        sleep 0.1
        reap_count=$((reap_count + 1))
    done
    if kill -0 "$reap_pid" 2>/dev/null; then
        echo "Test child $reap_pid did not exit after KILL" >&2
        return 1
    fi
    wait "$reap_pid" 2>/dev/null || :
}
cleanup()
{
    cleanup_error=0
    # Failure/cancellation fallback: unblock only the server created by this test.
    if server_owned; then kill -CONT "$server" 2>/dev/null || :; fi
    if [ -n "$launcher" ]; then
        kill -TERM "$launcher" 2>/dev/null || :
        cleanup_count=0
        while kill -0 "$launcher" 2>/dev/null && [ "$cleanup_count" -lt 12 ]; do
            sleep 1
            cleanup_count=$((cleanup_count + 1))
        done
        if kill -0 "$launcher" 2>/dev/null; then
            kill -KILL "$launcher" 2>/dev/null || :
        fi
        reap_if_gone "$launcher" || cleanup_error=1
    fi
    if [ -n "$session" ] && [ -x "$session/session-processes" ]; then
        EMBERBSD_ENLIGHTENMENT_SESSION=$session "$session/session-processes" \
            --signal KILL > "$result/fallback-kill.pids" 2> "$result/fallback-kill.log" || :
    fi
    if server_owned; then kill -KILL "$server" 2>/dev/null || :; fi
    if [ -n "$blocked" ]; then
        kill -KILL "$blocked" 2>/dev/null || :
        reap_if_gone "$blocked" || cleanup_error=1
    fi
    # This direct child remains unreaped until cleanup, preventing PID reuse.
    if [ -n "$sentinel" ]; then
        kill -KILL "$sentinel" 2>/dev/null || :
        reap_if_gone "$sentinel" || cleanup_error=1
    fi
    if [ -n "$session" ] && [ -f "$work/last-session.txt" ] &&
        [ "$(cat "$work/last-session.txt")" = "$session" ]; then
        if [ "$old_latest" = true ]; then
            cp "$result/last-session.before" "$work/last-session.txt"
        else
            rm "$work/last-session.txt"
        fi
    fi
    # SIGKILL cannot run Xvfb's socket/lock cleanup. Remove only :80 state
    # with our saved owner PID, after confirming that process has disappeared.
    if [ -n "$server" ] && ! kill -0 "$server" 2>/dev/null &&
        [ -f /tmp/.X80-lock ] &&
        [ "$(tr -d '[:space:]' < /tmp/.X80-lock)" = "$server" ]; then
        printf 'Removed confirmed stale X80 lock/socket for test PID %s\n' "$server" \
            > "$result/stale-x80-cleanup.log"
        rm -f /tmp/.X80-lock /tmp/.X11-unix/X80
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

cc -std=c99 -D_NETBSD_SOURCE -O2 -Wall -Wextra -Werror \
    "$recipe/tests/process-scope/scope-child.c" -o "$result/scope-child"
ENLIGHTENMENT_DISPLAY_NUMBER=80 sh "$recipe/run-nested.sh" "$work" --headless \
    > "$result/launcher.log" 2>&1 &
launcher=$!
printf '%s\n' "$launcher" > "$result/launcher.pid"
count=0
while [ -z "$session" ] || [ ! -s "$session/runtime/bus-address" ]; do
    kill -0 "$launcher" || { cat "$result/launcher.log" >&2; exit 1; }
    count=$((count + 1))
    [ "$count" -lt 25 ] || { echo 'Launcher startup timed out' >&2; exit 1; }
    sleep 1
    session=$(sed -n 's/^Enlightenment session: //p' "$result/launcher.log")
done
case "$session" in "$work"/session.*) ;; *) echo 'Unexpected launcher session path' >&2; exit 1 ;; esac
[ "$(cat "$session/display")" = :80 ]
server=$(cat "$session/xserver.pid")
server_owned || { echo 'The Xvfb PID does not belong to this test' >&2; exit 1; }
printf '%s\n' "$session" > "$result/session.txt"
DISPLAY=:80
export DISPLAY
unset XAUTHORITY DBUS_SESSION_BUS_ADDRESS
count=0
while :; do
    timeout --foreground -k 1 2 xprop -root _NET_SUPPORTING_WM_CHECK \
        > "$result/wm-root.log" 2>&1 || :
    owner=$(sed -n 's/.*window id # \(0x[0-9a-fA-F]*\).*/\1/p' "$result/wm-root.log")
    if [ -n "$owner" ] && [ "$owner" != 0x0 ]; then
        if timeout --foreground -k 1 2 xprop -id "$owner" _NET_WM_NAME \
            > "$result/wm-name.log" 2>&1 && grep -q '"Enlightenment"' "$result/wm-name.log"; then
            break
        fi
    fi
    count=$((count + 1))
    [ "$count" -lt 20 ] || { echo 'Enlightenment did not claim X11 WM ownership' >&2; exit 1; }
    sleep 1
done
printf 'PASS: actual Enlightenment WM owns dedicated display :80\n'

# The intermediate shell exits; session-exec calls setsid before exec.
# The resulting orphan ignores TERM and is outside the launcher's PGIDs.
EMBERBSD_ENLIGHTENMENT_SESSION=$session sh -c \
    '"$1" "$2" ignore "$3" > "$4" 2>&1 < /dev/null &' fixture-launch \
    "$session/session-exec" "$result/scope-child" "$result/orphan.pid" "$result/orphan.log"
"$result/scope-child" normal "$result/sentinel.pid" & sentinel=$!
count=0
while [ ! -s "$result/orphan.pid" ] || [ ! -s "$result/sentinel.pid" ]; do
    count=$((count + 1))
    [ "$count" -lt 50 ] || { echo 'Fixture startup timed out' >&2; exit 1; }
    sleep 0.1
done
read -r orphan orphan_group orphan_session < "$result/orphan.pid"
[ "$orphan" = "$orphan_group" ] && [ "$orphan" = "$orphan_session" ]
[ "$(ps -p "$orphan" -o ppid= | tr -d ' ')" -eq 1 ]
EMBERBSD_ENLIGHTENMENT_SESSION=$session "$session/session-processes" --check > "$result/initial-scope.pids"
grep -qx "$orphan" "$result/initial-scope.pids"
if grep -qx "$sentinel" "$result/initial-scope.pids"; then
    echo 'The untagged sentinel entered the session scope' >&2
    exit 1
fi
for pid in "$launcher" "$server" "$orphan" "$sentinel"; do
    ps -p "$pid" -o pid,ppid,pgid,stat,args
done > "$result/before-stop.ps"
kill -STOP "$server"
ps -p "$server" -o stat= > "$result/stopped-server.stat"
grep -q T "$result/stopped-server.stat"
EMBERBSD_ENLIGHTENMENT_SESSION=$session xprop -root _NET_SUPPORTING_WM_CHECK \
    > "$result/blocked-xprop.log" 2>&1 & blocked=$!
sleep 1
kill -0 "$blocked"
EMBERBSD_ENLIGHTENMENT_SESSION=$session "$session/session-processes" --check > "$result/stalled-scope.pids"
grep -qx "$blocked" "$result/stalled-scope.pids"
printf 'PASS: owned Xvfb stopped; marked Xlib client blocked; setsid orphan ignores TERM\n'

started=$(date +%s)
kill -TERM "$launcher"
count=0
while kill -0 "$launcher" 2>/dev/null; do
    count=$((count + 1))
    [ "$count" -le 12 ] || { echo 'Launcher cancellation exceeded 12 seconds' >&2; exit 1; }
    sleep 1
done
rc=0
wait "$launcher" || rc=$?
launcher=
elapsed=$(( $(date +%s) - started ))
printf '%s\n' "$rc" > "$result/launcher-status"
printf '%s\n' "$elapsed" > "$result/elapsed-seconds"
[ "$rc" -eq 143 ] || { echo "Expected launcher status 143, got $rc" >&2; exit 1; }
[ "$elapsed" -le 12 ] || { echo "Cancellation took $elapsed seconds" >&2; exit 1; }
if kill -0 "$server" 2>/dev/null; then echo 'Owned Xvfb remained alive' >&2; exit 1; fi
if kill -0 "$orphan" 2>/dev/null; then echo 'Tagged setsid orphan remained alive' >&2; exit 1; fi
rc=0
EMBERBSD_ENLIGHTENMENT_SESSION=$session "$session/session-processes" --check > "$result/remaining.pids" || rc=$?
[ "$rc" -eq 1 ] || { echo "Cleanup not confirmed (scope status $rc)" >&2; exit 1; }
wait "$blocked" 2>/dev/null || :
blocked=
kill -0 "$sentinel"
[ ! -d /tmp/emberbsd-enlightenment-x80.lock ] || { echo 'Launcher display reservation remained' >&2; exit 1; }
if [ -e /tmp/.X80-lock ] || [ -e /tmp/.X11-unix/X80 ]; then
    ls -l /tmp/.X80-lock /tmp/.X11-unix/X80 > "$result/stale-x80-state.log" 2>&1 || :
    echo 'Launcher left owned X80 socket/lock state' >&2
    exit 1
fi
printf 'PASS: cancellation returned 143 in %s seconds; Xvfb and tagged processes gone; untagged sentinel survived\n' "$elapsed"
printf 'Evidence: %s\nSession: %s\n' "$result" "$session"
