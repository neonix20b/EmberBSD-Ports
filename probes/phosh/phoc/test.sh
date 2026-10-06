#!/bin/sh
# Run upstream protocol tests on an isolated X server, without resizing the desktop.
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: sh test.sh ABSOLUTE_BUILD_DIRECTORY' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Build directory must be absolute.' >&2; exit 2 ;; esac
PATH=/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin
LD_LIBRARY_PATH="$work/prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
XDG_DATA_DIRS="$work/prefix/share:/usr/pkg/share:/usr/share"
export PATH LD_LIBRARY_PATH XDG_DATA_DIRS
command -v Xvfb >/dev/null
[ -x "$work/phoc-build/src/phoc" ]
tmp=$(mktemp -d "$work/test-xvfb.XXXXXXXX")
xvfb=
cleanup()
{
    if [ -n "$xvfb" ]; then
        kill "$xvfb" 2>/dev/null || true
        wait "$xvfb" 2>/dev/null || true
    fi
    rm -f "$tmp/display"
    rmdir "$tmp"
}
trap cleanup EXIT HUP INT TERM
Xvfb -displayfd 3 -screen 0 2048x2048x24 -nolisten tcp \
    3> "$tmp/display" > "$work/logs/xvfb.log" 2>&1 < /dev/null &
xvfb=$!
i=0
while [ ! -s "$tmp/display" ]; do
    kill -0 "$xvfb"
    i=$((i + 1))
    [ "$i" -lt 10 ] || { echo 'Xvfb startup timed out.' >&2; exit 1; }
    sleep 1
done
DISPLAY=:$(cat "$tmp/display")
export DISPLAY
unset XAUTHORITY
status=0
dbus-run-session -- meson test -C "$work/phoc-build" --no-rebuild \
    --num-processes 1 --print-errorlogs > "$work/logs/phoc-test.log" 2>&1 || status=$?
cat "$work/logs/phoc-test.log"
exit "$status"
