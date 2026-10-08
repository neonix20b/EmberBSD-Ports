#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), actual private session-bus roundtrips.
set -eu
[ "$#" = 1 ]
[ -n "${DBUS_SESSION_BUS_ADDRESS-}" ]
logs=$1
name=org.EmberBSD.DesktopAcceptance
echo_pid=
cleanup() {
    if [ -n "$echo_pid" ]; then kill "$echo_pid" 2>/dev/null || :; wait "$echo_pid" 2>/dev/null || :; fi
}
trap cleanup EXIT HUP INT TERM
bus() {
    dbus-send --session --print-reply --reply-timeout=2000 --dest=org.freedesktop.DBus \
        /org/freedesktop/DBus "org.freedesktop.DBus.$@"
}
bus GetId > "$logs/id"
grep -Eq 'string "[0-9a-f]{32}"' "$logs/id"
bus ListNames > "$logs/names"
grep -Fq 'string "org.freedesktop.DBus"' "$logs/names"
bus GetConnectionUnixProcessID string:org.freedesktop.DBus > "$logs/bus-pid.reply"
sed -n 's/^ *uint32 \([0-9][0-9]*\)$/\1/p' "$logs/bus-pid.reply" > "$logs/bus-pid"
awk 'END {exit NR != 1}' "$logs/bus-pid"
bus NameHasOwner "string:$name" > "$logs/owner-before"
grep -Fq 'boolean false' "$logs/owner-before"
dbus-test-tool echo --session --name="$name" > "$logs/echo.out" 2> "$logs/echo.err" &
echo_pid=$!
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    bus NameHasOwner "string:$name" > "$logs/owner-ready"
    if grep -Fq 'boolean true' "$logs/owner-ready"; then ready=1; break; fi
    kill -0 "$echo_pid"
    sleep 0.1
done
[ "$ready" = 1 ]
bus GetNameOwner "string:$name" > "$logs/echo-owner"
owner=$(sed -n 's/^ *string "\(:[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' "$logs/echo-owner")
[ -n "$owner" ]
for request in 1 2 3 4 5 6 7 8; do
    dbus-send --session --print-reply --reply-timeout=2000 --dest="$name" \
        /org/EmberBSD/Test org.EmberBSD.Test.Roundtrip "uint32:$request" > "$logs/reply-$request"
    awk -v sender="sender=$owner" 'NR == 1 && $1 == "method" && $2 == "return" {
        for (i=3; i<=NF; i++) if ($i == sender) found=1
    } END {exit !(NR == 1 && found)}' "$logs/reply-$request"
done
# The upstream echo tool returns an empty method reply, not the request payload.
code=0
bus NoSuchMethod > "$logs/unknown-method" 2>&1 || code=$?
[ "$code" = 1 ]
grep -Fq 'org.freedesktop.DBus.Error.UnknownMethod' "$logs/unknown-method"
code=0
dbus-send --session --print-reply --reply-timeout=2000 --dest=org.EmberBSD.Missing \
    /org/EmberBSD/Test org.EmberBSD.Test.Roundtrip > "$logs/unknown-service" 2>&1 || code=$?
[ "$code" = 1 ]
grep -Fq 'org.freedesktop.DBus.Error.ServiceUnknown' "$logs/unknown-service"
kill "$echo_pid"
wait "$echo_pid" 2>/dev/null || :
echo_pid=
released=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    bus NameHasOwner "string:$name" > "$logs/owner-after"
    if grep -Fq 'boolean false' "$logs/owner-after"; then released=1; break; fi
    sleep 0.1
done
[ "$released" = 1 ]
[ ! -s "$logs/echo.err" ]
echo 'PASS: session D-Bus ownership, eight empty replies, explicit errors and owner release'
