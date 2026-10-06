#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 EmberBSD contributors. AI-assisted contract probe.
set -eu
umask 077
client=${1:?Usage: test-service-preflight.sh client-probe qml-client-probe new-directory}
qml=${2:?}
root=${3:?}
mkdir "$root"
cat > "$root/owned-service.sh" <<'EOF'
#!/bin/sh
set -eu
program=$1
service=$2
dbus-test-tool echo --session --name="$service" >/dev/null 2>&1 &
owner_pid=$!
trap 'kill "$owner_pid" 2>/dev/null || :; wait "$owner_pid" 2>/dev/null || :' EXIT HUP INT TERM
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.NameHasOwner "string:$service" | grep -F 'boolean true' >/dev/null; then
        ready=1
        break
    fi
    sleep 0.1
done
[ "$ready" -eq 1 ] || exit 3
export DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
"$program"
EOF
case_number=0
for service in org.freedesktop.ModemManager1 org.freedesktop.NetworkManager org.bluez; do
    case_number=$((case_number + 1))
    profile="$root/activatable-$case_number"
    mkdir -p "$profile/config" "$profile/data/dbus-1/services" "$profile/cache" "$profile/run"
    # Metadata-only fixture; an incorrect preflight must never reach activation.
    cat > "$profile/data/dbus-1/services/$service.service" <<EOF
[D-BUS Service]
Name=$service
Exec=/usr/bin/false
EOF
    for program in "$client" "$qml"; do
        output="$profile/$(basename "$program").log"
        if XDG_CONFIG_HOME="$profile/config" XDG_DATA_HOME="$profile/data" \
            XDG_CACHE_HOME="$profile/cache" XDG_RUNTIME_DIR="$profile/run" \
            timeout -k 2 15 dbus-run-session -- /bin/sh -c \
            'export DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS; exec "$@"' sh "$program" > "$output" 2>&1; then
            status=0
        else
            status=$?
        fi
        [ "$status" -eq 2 ] || { echo "Expected preflight refusal for $service: $output" >&2; exit 1; }
        grep -Fx "System D-Bus preflight rejected: service is activatable: $service" "$output" >/dev/null
        if grep -E 'Loaded real QML module:|Real Qt D-Bus clients:' "$output"; then
            echo 'Client work ran after preflight refusal.' >&2
            exit 1
        fi
    done
    # The stock D-Bus test tool owns a name only on this private fixture bus.
    for program in "$client" "$qml"; do
        output="$profile/owned-$(basename "$program").log"
        if timeout -k 2 15 dbus-run-session -- /bin/sh "$root/owned-service.sh" "$program" "$service" > "$output" 2>&1; then
            status=0
        else
            status=$?
        fi
        [ "$status" -eq 2 ] || { echo "Expected owned-name refusal: $output" >&2; exit 1; }
        grep -Fx "System D-Bus preflight rejected: service is owned: $service" "$output" >/dev/null
    done
done
cat > "$root/deny-activatable.conf" <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
    <deny send_destination="org.freedesktop.DBus" send_interface="org.freedesktop.DBus" send_member="ListActivatableNames"/>
  </policy>
</busconfig>
EOF
for program in "$client" "$qml"; do
    output="$root/denied-query-$(basename "$program").log"
    if timeout -k 2 15 dbus-run-session --config-file="$root/deny-activatable.conf" -- /bin/sh -c \
        'export DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS; exec "$@"' sh "$program" > "$output" 2>&1; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq 2 ] || { echo "Expected query-error refusal: $output" >&2; exit 1; }
    grep -F 'System D-Bus preflight rejected: query failed: ListActivatableNames ' "$output" >/dev/null
done
# A missing bus must fail closed before any client is constructed.
for program in "$client" "$qml"; do
    output="$root/unavailable-$(basename "$program").log"
    if DBUS_SYSTEM_BUS_ADDRESS="unix:path=$root/no-bus" timeout -k 2 15 "$program" > "$output" 2>&1; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq 2 ] || { echo "Expected unavailable-bus refusal: $output" >&2; exit 1; }
    grep -Fx 'System D-Bus preflight rejected: bus is unavailable.' "$output" >/dev/null
done
echo 'Service preflight regression passed: 16 cases'
