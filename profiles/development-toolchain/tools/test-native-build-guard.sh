#!/bin/sh
# AI-assisted EmberBSD regression checks for the native GCC build guard.
set -eu
if [ "$#" -ne 3 ]; then
    echo "usage: $0 guard fresh-test-directory mounted-scratch" >&2
    exit 64
fi
guard=$1
out=$2
scratch=$3
mkdir "$out"
case_status()
{
    expected=$1
    dir=$2
    shift 2
    if "$guard" "$dir" "$scratch" 1048576 2097152 -- "$@"; then rc=0; else rc=$?; fi
    test "$rc" -eq "$expected"
    test "$(cat "$dir/status")" -eq "$expected"
}
mkdir "$out/zero" "$out/seven" "$out/full" "$out/signal" "$out/mount-loss"
case_status 0 "$out/zero" /bin/sh -c 'echo child-success'
case_status 7 "$out/seven" /bin/sh -c 'exit 7'
if "$guard" "$out/full" "$scratch" 1048576 18446744073709551615 -- /bin/sh -c 'touch should-not-run'; then rc=0; else rc=$?; fi
test "$rc" -eq 75
test "$(cat "$out/full/status")" -eq 75
test ! -e "$out/full/should-not-run"
if "$guard" "$out/zero" "$scratch" 1048576 2097152 -- /bin/false; then rc=0; else rc=$?; fi
test "$rc" -eq 74
test "$(cat "$out/zero/status")" -eq 0
if "$guard" "$out/full" / 1048576 2097152 -- /bin/false; then rc=0; else rc=$?; fi
test "$rc" -eq 75
# An unrelated process must survive both signal and mount-loss shutdowns.
sleep 120 &
outsider=$!
trap 'kill "$outsider"; wait "$outsider" 2>/dev/null || :' EXIT
for mode in signal mount-loss; do
    ln -s "$scratch" "$out/$mode-scratch"
    "$guard" "$out/$mode" "$out/$mode-scratch" 1048576 2097152 -- /bin/sh -c 'trap "" TERM; sleep 120 & echo $! > grandchild.pid; wait' &
    supervisor=$!
    tries=0
    while [ ! -s "$out/$mode/grandchild.pid" ] || [ ! -s "$out/$mode/child.pgid" ]; do
        tries=$((tries + 1))
        test "$tries" -le 20
        sleep 1
    done
    if [ "$mode" = signal ]; then
        kill -TERM "$supervisor"
        expected=143
    else
        rm "$out/$mode-scratch"
        ln -s / "$out/$mode-scratch"
        expected=75
    fi
    if wait "$supervisor"; then rc=0; else rc=$?; fi
    test "$rc" -eq "$expected"
    test "$(cat "$out/$mode/status")" -eq "$expected"
    kill -0 "$outsider"
    group=$(cat "$out/$mode/child.pgid")
    # Ignore dead zombies awaiting init; no live process may remain in our group.
    ps -axo pgid=,stat= | awk -v group="$group" '$1 == group && $2 !~ /^Z/ { found=1 } END { exit found }'
done
echo 'PASS exit0/7, resource refusal, stale run refusal, root mount refusal, isolated signal and mount-loss cleanup'
