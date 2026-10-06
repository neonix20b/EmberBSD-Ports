#!/bin/sh
# Run Stevia's component tests on an isolated X server.
set -eu
umask 077
ulimit -c 0
[ "$#" -eq 1 ] || { echo 'Usage: sh test.sh ABSOLUTE_BUILD_DIRECTORY' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Build directory must be absolute.' >&2; exit 2 ;; esac
support=$(cat "$work/support-prefix.txt")
phoc=$(cat "$work/phoc-prefix.txt")
PATH="$work/tools:/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin"
LD_LIBRARY_PATH="$work/install/lib:$support/lib:$phoc/lib:/usr/pkg/lib:/usr/X11R7/lib"
XDG_DATA_DIRS="$work/install/share:$support/share:$phoc/share:/usr/pkg/share:/usr/share"
GDK_BACKEND=x11
export PATH LD_LIBRARY_PATH XDG_DATA_DIRS GDK_BACKEND
command -v Xvfb >/dev/null
command -v cc >/dev/null
[ -x "$work/install/bin/phosh-osk-stevia" ]
tmp=$(mktemp -d "$work/test-xvfb.XXXXXXXX")
xvfb=
runner=
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
    # Do not make the cleanup deadline depend on an uninterruptible child.
    for pid in "$runner" "$xvfb"; do
        [ -n "$pid" ] || continue
        if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" 2>/dev/null || true; fi
    done
    rm -f "$tmp/display" "$tmp/session-exec" "$tmp/session-exec.c" || cleanup_status=1
    rmdir "$tmp" || cleanup_status=1
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
# NetBSD has setsid(2), but no setsid command. Keep this launcher private.
cat > "$tmp/session-exec.c" <<'C'
#include <sys/types.h>
#include <unistd.h>
#include <stdio.h>
int
main(int argc, char **argv)
{
    if (argc < 2)
        return 2;
    if (setsid() == -1) {
        perror("setsid");
        return 1;
    }
    execvp(argv[1], argv + 1);
    perror(argv[1]);
    return 127;
}
C
cc -o "$tmp/session-exec" "$tmp/session-exec.c"
"$tmp/session-exec" Xvfb -displayfd 3 -screen 0 1024x768x24 -nolisten tcp \
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
unset XAUTHORITY WAYLAND_DISPLAY
status=0
"$tmp/session-exec" dbus-run-session -- meson test -C "$work/build" --no-rebuild \
    --num-processes 1 --print-errorlogs > "$work/logs/test.log" 2>&1 < /dev/null &
runner=$!
# Waiting for a background job lets shell signal traps run immediately.
wait "$runner" || status=$?
cat "$work/logs/test.log"
exit "$status"
