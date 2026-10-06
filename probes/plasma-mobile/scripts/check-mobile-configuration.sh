#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Regress Mobile's real immutable keyboard default in a private profile.
set -eu
[ "$(uname -s)" = NetBSD ] || { echo 'Run on EmberBSD/NetBSD.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
[ "$#" -eq 1 ] || { echo 'Usage: check-mobile-configuration.sh BUILD_ROOT' >&2; exit 2; }
root=$1
case "$root" in /*) ;; *) echo 'Use an absolute build root.' >&2; exit 2 ;; esac
prefix=$root/install
umask 077
session=$(mktemp -d "$root/mobile-config.XXXXXX")
mkdir "$session/config" "$session/data" "$session/cache" "$session/runtime"
export PATH="$prefix/bin:/usr/pkg/bin:/usr/pkg/qt6/bin:/usr/bin:/bin"
export LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/pkg/qt6/lib:/usr/X11R7/lib"
export XDG_CONFIG_HOME="$session/config" XDG_DATA_HOME="$session/data"
export XDG_CACHE_HOME="$session/cache" XDG_RUNTIME_DIR="$session/runtime"
export XDG_CONFIG_DIRS="$XDG_CONFIG_HOME/plasma-mobile:/usr/pkg/etc/xdg"
export XDG_DATA_DIRS="$prefix/share:/usr/pkg/share:/usr/share"
export PLASMA_PLATFORM=phone:handset QT_QPA_PLATFORM=offscreen LC_ALL=C.UTF-8 LD_BIND_NOW=1
unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET
unset DBUS_SESSION_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE
case ${MOBILE_CONFIG_TIMEOUT:-20} in ''|*[!0-9]*) exit 2 ;; esac
[ "${MOBILE_CONFIG_TIMEOUT:-20}" -ge 1 ] && [ "${MOBILE_CONFIG_TIMEOUT:-20}" -le 60 ] || exit 2
worker=
worker_alive()
{
    kill -0 "$worker" 2>/dev/null || kill -0 -- "-$worker" 2>/dev/null
}
stop_worker()
{
    [ -n "$worker" ] || return 0
    for signal in TERM KILL; do
        kill -s "$signal" -- "-$worker" 2>/dev/null || :
        kill -s "$signal" "$worker" 2>/dev/null || :
        count=0
        while worker_alive && [ "$count" -lt 2 ]; do
            sleep 1
            count=$((count + 1))
        done
        worker_alive || break
    done
    if worker_alive; then
        echo "Configuration process group $worker did not exit." >&2
        return 1
    fi
    wait "$worker" 2>/dev/null || :
    worker=
}
finish()
{
    result=$?
    trap - EXIT
    trap '' HUP INT TERM
    stop_worker || { [ "$result" -ne 0 ] || result=1; }
    exit "$result"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
run_checked()
{
    # Default timeout mode owns a process group, including D-Bus and children.
    timeout -k 2 "${MOBILE_CONFIG_TIMEOUT:-20}" "$@" &
    worker=$!
    printf '%s\n' "$worker" >>"$session/worker-pids.txt"
    command_status=0
    wait "$worker" || command_status=$?
    stop_worker || return 1
    return "$command_status"
}
cat >"$session/bus.conf" <<EOF
<busconfig>
  <type>session</type>
  <listen>unix:path=$XDG_RUNTIME_DIR/bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow user="$(id -u)"/>
    <allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/>
  </policy>
</busconfig>
EOF
run_checked dbus-run-session --config-file="$session/bus.conf" -- \
    plasma-mobile-envmanager --apply-settings >"$session/check.log" 2>&1
run_checked kreadconfig6 --file kwinrc --group Wayland --key VirtualKeyboardEnabled >"$session/keyboard.txt"
[ "$(cat "$session/keyboard.txt")" = true ]
grep -Fx 'VirtualKeyboardEnabled[$i]=true' "$XDG_CONFIG_HOME/plasma-mobile/kwinrc" >>"$session/check.log"
# This old launcher operation must fail because the generated entry is locked.
write_status=0
run_checked kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardEnabled true || write_status=$?
[ "$write_status" -eq 2 ]
run_checked kreadconfig6 --file kwinrc --group Wayland --key VirtualKeyboardEnabled >"$session/keyboard-after.txt"
[ "$(cat "$session/keyboard-after.txt")" = true ]
printf 'PASS immutable Mobile keyboard default; read succeeds; redundant write returns %s\n' "$write_status" >>"$session/check.log"
cat "$session/check.log"
printf 'Configuration regression passed. Evidence: %s\n' "$session"
