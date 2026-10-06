#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Run as an ordinary user on NetBSD. Only processes created here are targeted.
set -eu
umask 077
[ "$(id -u)" -ne 0 ] || { echo 'Run this test as a non-root user' >&2; exit 2; }
base=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
helper=$base/session-processes
fixture=$base/scope-child
work=$(mktemp -d "$base/run.XXXXXXXX")
cancel_ready=
if [ "$#" -eq 2 ] && [ "$1" = '--cancel-ready' ]; then
    cancel_ready=$2
elif [ "$#" -ne 0 ]; then
    echo 'Usage: test-session-processes.sh [--cancel-ready ABSOLUTE_FILE]' >&2
    exit 2
fi
scope=$work/session
other=$scope-other
mkdir "$scope" "$other"
normal= orphan= stubborn= sentinel= other_pid= late=

cleanup()
{
    trap - EXIT HUP INT TERM
    # Both markers belong to this test; never signal a UID or process group.
    EMBERBSD_ENLIGHTENMENT_SESSION=$scope "$helper" --signal KILL >/dev/null 2>&1 || :
    EMBERBSD_ENLIGHTENMENT_SESSION=$other "$helper" --signal KILL >/dev/null 2>&1 || :
    # The untagged sentinel remains our unreaped direct child, so its PID cannot be reused.
    if [ -n "$sentinel" ]; then kill -KILL "$sentinel" 2>/dev/null || :; fi
    wait 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

wait_file()
{
    count=0
    while [ ! -s "$1" ]; do
        count=$((count + 1))
        [ "$count" -lt 50 ] || { echo "Fixture did not start: $1" >&2; exit 1; }
        sleep 0.1
    done
}
expect_status()
{
    expected=$1
    shift
    rc=0
    "$@" || rc=$?
    [ "$rc" -eq "$expected" ] || {
        echo "Expected exit $expected, got $rc: $*" >&2
        exit 1
    }
}
wait_empty()
{
    count=0
    while :; do
        rc=0
        "$helper" --check > "$work/remaining" || rc=$?
        [ "$rc" -ne 2 ] || { echo 'Process scan incomplete' >&2; exit 1; }
        [ "$rc" -ne 1 ] || return 0
        count=$((count + 1))
        [ "$count" -lt 50 ] || { echo 'Tagged processes remained' >&2; exit 1; }
        sleep 0.1
    done
}

# New helpers exec with this token; their direct test-shell parent must survive.
export EMBERBSD_ENLIGHTENMENT_SESSION=$scope
expect_status 1 "$helper" --check
expect_status 2 env -u EMBERBSD_ENLIGHTENMENT_SESSION "$helper" --check
expect_status 2 env EMBERBSD_ENLIGHTENMENT_SESSION=relative "$helper" --signal TERM
"$fixture" normal "$work/normal.pid" & normal=$!
"$fixture" orphan "$work/orphan.pid" & orphan_parent=$!
"$fixture" ignore "$work/stubborn.pid" & stubborn=$!
env -u EMBERBSD_ENLIGHTENMENT_SESSION "$fixture" normal "$work/sentinel.pid" & sentinel=$!
env EMBERBSD_ENLIGHTENMENT_SESSION=$other "$fixture" normal "$work/other.pid" & other_pid=$!
for kind in normal orphan stubborn sentinel other; do wait_file "$work/$kind.pid"; done
wait "$orphan_parent"
read -r orphan orphan_pgid orphan_sid < "$work/orphan.pid"
[ "$orphan" = "$orphan_pgid" ] && [ "$orphan" = "$orphan_sid" ]
"$helper" --check > "$work/matches"
for pid in "$normal" "$orphan" "$stubborn"; do grep -qx "$pid" "$work/matches"; done
[ "$(wc -l < "$work/matches" | tr -d ' ')" -eq 3 ]
if [ -n "$cancel_ready" ]; then
    printf '%s\n' "$work" > "$cancel_ready"
    count=0
    while [ "$count" -lt 20 ]; do
        sleep 1
        count=$((count + 1))
    done
    echo 'Cancellation test did not receive a signal' >&2
    exit 1
fi
"$helper" --signal TERM > "$work/term"
wait "$normal" 2>/dev/null || :
# An ignored TERM requires a later, fresh KILL pass.
kill -0 "$stubborn"
kill -0 "$sentinel"
kill -0 "$other_pid"
"$helper" --signal KILL > "$work/kill"
wait "$stubborn" 2>/dev/null || :
wait_empty
kill -0 "$sentinel"
kill -0 "$other_pid"

# An application launched after the previous pass must be found by a fresh scan.
"$fixture" normal "$work/late.pid" & late=$!
wait_file "$work/late.pid"
"$helper" --check > "$work/late-matches"
grep -qx "$late" "$work/late-matches"
"$helper" --signal TERM > "$work/late-term"
wait "$late" 2>/dev/null || :
wait_empty
kill -0 "$sentinel"
kill -0 "$other_pid"
printf 'PASS: normal + setsid orphan + TERM-resistant processes removed; untagged and other-marker sentinels survived; fresh scan found late child\n'
printf 'Evidence: %s\n' "$work"
