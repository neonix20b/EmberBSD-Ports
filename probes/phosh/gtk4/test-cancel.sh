#!/bin/sh
# Stop this test's compositor group, then verify bounded TERM cancellation.
set -eu
umask 077
[ "$#" -eq 3 ] || { echo 'Usage: sh test-cancel.sh GTK_PREFIX PHOC_PREFIX NEW_WORK_DIRECTORY' >&2; exit 2; }
gtk=$1
phoc=$2
work=$3
case "$work" in /*) ;; *) echo 'Use an absolute test directory.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a path without shell metacharacters.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
display_number=${GTK4_TEST_DISPLAY_NUMBER:-89}
mkdir "$work"
launcher=
runner=
xvfb=
cleanup()
{
    for pid in "$launcher" "$runner" "$xvfb"; do
        [ -n "$pid" ] || continue
        kill -s TERM "$pid" 2>/dev/null || true
    done
    for pid in "$runner" "$xvfb"; do
        [ -n "$pid" ] || continue
        kill -s CONT -- "-$pid" 2>/dev/null || true
        kill -s TERM -- "-$pid" 2>/dev/null || true
    done
    if [ -n "$launcher" ]; then
        i=0
        while kill -0 "$launcher" 2>/dev/null && [ "$i" -lt 8 ]; do
            sleep 1
            i=$((i + 1))
        done
        kill -s KILL "$launcher" 2>/dev/null || true
    fi
    for pid in "$runner" "$xvfb"; do
        [ -n "$pid" ] || continue
        kill -s KILL -- "-$pid" 2>/dev/null || true
    done
}
finish()
{
    status=$?
    trap - EXIT
    trap '' HUP INT TERM
    cleanup
    exit "$status"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
GTK4_TEST_DISPLAY_NUMBER=$display_number sh "$recipe/test-runtime.sh" \
    "$gtk" "$phoc" "$work/run" > "$work/helper.log" 2>&1 < /dev/null &
launcher=$!
i=0
while [ ! -s "$work/run/runner.pid" ] || [ ! -f "$work/run/client.log" ]; do
    kill -0 "$launcher" 2>/dev/null || {
        cat "$work/helper.log" >&2
        echo 'Runtime helper exited before the cancellation point.' >&2
        exit 1
    }
    i=$((i + 1))
    [ "$i" -le 15 ] || { echo 'Runtime helper startup timed out.' >&2; exit 1; }
    sleep 1
done
runner=$(cat "$work/run/runner.pid")
xvfb=$(cat "$work/run/xvfb.pid")
# A stopped group cannot respond to TERM; cleanup must escalate to KILL.
kill -s STOP -- "-$runner"
kill -s TERM "$launcher"
i=0
while kill -0 "$launcher" 2>/dev/null && [ "$i" -lt 10 ]; do
    sleep 1
    i=$((i + 1))
done
if kill -0 "$launcher" 2>/dev/null; then
    echo 'FAIL: cancellation exceeded ten seconds.' >&2
    exit 1
fi
status=0
wait "$launcher" || status=$?
launcher=
printf '%s\n' "$status" > "$work/exit-status"
[ "$status" -eq 143 ] || { echo "FAIL: expected TERM status 143, got $status." >&2; exit 1; }
for pid in "$runner" "$xvfb"; do
    if kill -0 -- "-$pid" 2>/dev/null || kill -0 "$pid" 2>/dev/null; then
        echo "FAIL: test process group $pid survived cancellation." >&2
        exit 1
    fi
done
[ ! -e "/tmp/.X11-unix/X$display_number" ]
[ ! -e "/tmp/.X$display_number-lock" ]
[ ! -e "/tmp/emberbsd-gtk4-x$display_number.lock" ]
runner=
xvfb=
printf 'PASS: stopped compositor cancelled in %s seconds with status 143; own groups and display released.\n' "$i"
