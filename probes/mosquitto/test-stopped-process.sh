#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# AI-assisted regression for the lifecycle verifier's live-process rejection.
set -eu
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
    echo 'Usage: test-stopped-process.sh NEW_WORK [SOURCE_VERIFIER]' >&2; exit 2
}
work=$1
case "$work" in /*) ;; *) exit 2 ;; esac
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source=${2:-$here/test-rc-service.sh}
mkdir "$work"
awk '
/^require_stopped\(\)$/ { found++; active=1 }
active { print }
active && /^}$/ { active=0 }
END { if (found != 1 || active) exit 2 }
' "$source" > "$work/check.inc"
cat > "$work/check.sh" <<'EOF'
set -eu
. "$1"
require_stopped "$2"
echo 'ACCEPTED'
EOF
sleep 30 &
owned_pid=$!
cleanup()
{
    if [ -n "$owned_pid" ]; then
        kill "$owned_pid" 2>/dev/null || :
        wait "$owned_pid" 2>/dev/null || :
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
kill -0 "$owned_pid"
if sh "$work/check.sh" "$work/check.inc" "$owned_pid" > "$work/alive.log" 2>&1; then
    echo 'Verifier incorrectly accepted a live owned process.' >&2; exit 1
fi
! grep ACCEPTED "$work/alive.log" >/dev/null || exit 1
echo 'PASS: lifecycle verifier rejects a live owned process'
old_pid=$owned_pid
kill "$owned_pid"
wait "$owned_pid" 2>/dev/null || :
owned_pid=
sh "$work/check.sh" "$work/check.inc" "$old_pid" > "$work/stopped.log" 2>&1
grep '^ACCEPTED$' "$work/stopped.log" >/dev/null
echo 'PASS: lifecycle verifier accepts a reaped owned process'
