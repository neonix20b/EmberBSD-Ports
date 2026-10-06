#!/bin/sh
# SPDX-License-Identifier: MIT
# Local regression checks; no KWin, X server or VM is started.
set -eu
umask 077
recipe_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$recipe_dir/scripts/nested-lifecycle.sh"
scratch=$(mktemp -d /tmp/kwin-lifecycle.XXXXXX)
test_child=
test_bus=
test_cleanup()
{
    test_status=$?
    for pid in "$test_child" "$test_bus"; do
        [ -n "$pid" ] || continue
        kill -KILL "$pid" 2>/dev/null || :
        if child_exited "$pid" 2; then wait "$pid" 2>/dev/null || :; fi
    done
    if [ "$test_status" -eq 0 ]; then
        rm -rf "$scratch"
    else
        echo "Failed lifecycle check evidence: $scratch" >&2
    fi
}
trap test_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
${CC:-cc} -std=c99 -Wall -Wextra -Werror "$recipe_dir/scripts/lifecycle-exec.c" -o "$scratch/lifecycle-exec"
build_root=$scratch
saved_home=$HOME
prepare_profile
[ "$HOME" = "$saved_home" ]
for dir in "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"; do
    [ -d "$dir" ]
    [ "$(LC_ALL=C ls -ld "$dir" | cut -c1-10)" = drwx------ ]
done
WAYLAND_DISPLAY=kwin-contract
x_pid= kwin_pid= client_pid= bus_pid= display_guard=
x_socket=$scratch/X79
x_lock=$scratch/X79-lock
contract_complete=false

# A service in the private XDG_DATA_HOME must still not be activatable.
command -v dbus-daemon >/dev/null
command -v dbus-send >/dev/null
mkdir -p "$XDG_DATA_HOME/dbus-1/services"
cat >"$XDG_DATA_HOME/dbus-1/services/org.kde.kglobalaccel.service" <<EOF
[D-BUS Service]
Name=org.kde.kglobalaccel
Exec=/usr/bin/touch $scratch/activated
EOF
dbus-daemon --nofork --nosyslog --config-file="$run/bus.conf" --print-address=1 \
    >"$run/bus-address.txt" 2>"$run/dbus.log" &
test_bus=$!
bus_pid=$test_bus
count=0
until [ -s "$run/bus-address.txt" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; do
    kill -0 "$test_bus"
    count=$((count + 1)); [ "$count" -lt 10 ] || exit 1
    sleep 1
done
DBUS_SESSION_BUS_ADDRESS=$(head -n 1 "$run/bus-address.txt")
export DBUS_SESSION_BUS_ADDRESS
dbus-send --session --print-reply --reply-timeout=2000 --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus org.freedesktop.DBus.ListNames >"$run/names.txt"
if dbus-send --session --print-reply --reply-timeout=2000 --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus org.freedesktop.DBus.StartServiceByName \
    string:org.kde.kglobalaccel uint32:0 >"$run/activation.txt" 2>&1; then
    echo 'Unexpected activation success.' >&2; exit 1
fi
grep -q org.freedesktop.DBus.Error.ServiceUnknown "$run/activation.txt"
[ ! -e "$scratch/activated" ]
cleanup
! kill -0 "$test_bus" 2>/dev/null
test_bus=
bus_pid=
[ ! -e "$XDG_RUNTIME_DIR/bus" ]
echo 'PASS private XDG before bus; HOME preserved; service activation unavailable'

# Normal termination and then forced termination, including stale owned nodes.
"$scratch/lifecycle-exec" default sh -c 'printf ready >"$1"; exec sleep 60' sh "$scratch/normal-ready" &
test_child=$!
count=0
until [ -f "$scratch/normal-ready" ]; do
    count=$((count + 1)); [ "$count" -lt 10 ] || exit 1
    sleep 1
done
stop_owned "$test_child" normal
! kill -0 "$test_child" 2>/dev/null
! grep -q '^forced=normal:' "$run/cleanup.txt"
test_child=
"$scratch/lifecycle-exec" ignore-term sh -c 'printf ready >"$1"; exec sleep 60' sh "$scratch/ready" &
test_child=$!
count=0
until [ -f "$scratch/ready" ]; do
    count=$((count + 1)); [ "$count" -lt 10 ] || exit 1
    sleep 1
done
x_pid=$test_child
printf '%s\n' "$x_pid" >"$x_lock"
touch "$x_socket" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY.lock"
display_guard=$scratch/guard
mkdir "$display_guard"
cleanup
! kill -0 "$test_child" 2>/dev/null
test_child=
x_pid=
grep -q '^forced=xvfb:' "$run/cleanup.txt"
[ ! -e "$x_socket" ] && [ ! -e "$x_lock" ] && [ ! -e "$display_guard" ]
display_guard=
echo 'PASS TERM, bounded KILL and removal of owned stale nodes'

# Failed KILL is simulated: it must return failure without entering wait.
(
    kill() { return 0; }
    sleep() { :; }
    wait() { touch "$scratch/unbounded-wait"; }
    if stop_owned 999999 stuck; then exit 1; fi
    [ ! -e "$scratch/unbounded-wait" ]
)
echo 'PASS failed KILL returns failure without wait'

# A foreign lock/socket survives, and cleanup failure suppresses PASS/status 0.
sleep 1 &
test_child=$!
child_exited "$test_child" 3
wait "$test_child" 2>/dev/null || :
x_pid=$test_child
test_child=
printf 'foreign\n' >"$x_lock"
touch "$x_socket"
status=0
(
    contract_complete=true
    trap finish EXIT
    exit 0
) >"$run/failed-cleanup.txt" 2>&1 || status=$?
[ "$status" -ne 0 ]
! grep -q '^PASS:' "$run/failed-cleanup.txt"
[ -e "$x_lock" ] && [ -e "$x_socket" ]
rm "$x_lock" "$x_socket"
x_pid=
echo 'PASS foreign nodes preserved; cleanup failure changes result and suppresses PASS'

# Use a new shell so $$ identifies the cancellation target, not this test.
cat >"$scratch/finish-probe.sh" <<'EOF'
#!/bin/sh
set -eu
. "$1"
run=$2
XDG_RUNTIME_DIR=$run/runtime
WAYLAND_DISPLAY=kwin-contract
x_socket=$run/test-X79
x_lock=$run/test-X79-lock
x_pid= kwin_pid= client_pid= bus_pid= display_guard=
contract_complete=true
trap finish EXIT
trap 'exit 143' TERM
sleep 60 &
client_pid=$!
printf '%s\n' "$client_pid" >"$run/finish-client.pid"
if [ "$3" = cancel ]; then kill -TERM "$$"; fi
exit 0
EOF
status=0
"$scratch/lifecycle-exec" default sh "$scratch/finish-probe.sh" "$recipe_dir/scripts/nested-lifecycle.sh" "$run" cancel \
    >"$run/cancel.txt" 2>&1 || status=$?
[ "$status" -eq 143 ]
! grep -q '^PASS:' "$run/cancel.txt"
! kill -0 "$(cat "$run/finish-client.pid")" 2>/dev/null
"$scratch/lifecycle-exec" default sh "$scratch/finish-probe.sh" "$recipe_dir/scripts/nested-lifecycle.sh" "$run" success \
    >"$run/success.txt" 2>&1
grep -q '^PASS:' "$run/success.txt"
[ "$(tail -n 1 "$run/cleanup.txt")" = cleanup_status=0 ]
! kill -0 "$(cat "$run/finish-client.pid")" 2>/dev/null
echo 'PASS cancellation status, successful final cleanup and restart'
