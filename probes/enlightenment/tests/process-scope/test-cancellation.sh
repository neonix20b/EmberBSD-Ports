#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d "$base/cancel.XXXXXXXX")
controller=
cleanup()
{
    trap - EXIT HUP INT TERM
    if [ -n "$controller" ]; then
        kill -TERM "$controller" 2>/dev/null || :
        wait "$controller" 2>/dev/null || :
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
env -u EMBERBSD_ENLIGHTENMENT_SESSION sh "$base/test-session-processes.sh" \
    --cancel-ready "$work/ready" > "$work/child.log" 2>&1 &
controller=$!
count=0
while [ ! -s "$work/ready" ]; do
    count=$((count + 1))
    [ "$count" -lt 50 ] || { echo 'Cancellation child did not become ready' >&2; exit 1; }
    sleep 0.1
done
IFS= read -r session_work < "$work/ready"
kill -TERM "$controller"
rc=0
wait "$controller" || rc=$?
controller=
[ "$rc" -eq 143 ] || { echo "Cancellation child exited $rc, expected 143" >&2; exit 1; }
for scope in "$session_work/session" "$session_work/session-other"; do
    rc=0
    EMBERBSD_ENLIGHTENMENT_SESSION=$scope "$base/session-processes" --check || rc=$?
    [ "$rc" -eq 1 ] || { echo "Cancellation left processes (status $rc)" >&2; exit 1; }
done
read -r sentinel rest < "$session_work/sentinel.pid"
if kill -0 "$sentinel" 2>/dev/null; then
    echo 'Cancellation left its untagged sentinel' >&2
    exit 1
fi
printf 'PASS: TERM cancellation cleaned tagged/orphan/other-marker test children and its untagged sentinel\n'
printf 'Evidence: %s\n' "$work"
