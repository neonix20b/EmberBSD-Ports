#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), verify DWARF expression and location-list repairs.
set -eu
[ "$#" = 3 ] || { echo "Usage: $0 GDB FIXTURES NEW_RESULTS" >&2; exit 2; }
gdb=$1 fixtures=$2 work=$3
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ]
[ -z "${LD_LIBRARY_PATH-}${LD_PRELOAD-}" ] || { echo 'Remove loader overrides.' >&2; exit 2; }
ulimit -c 0
ulimit -t 15
mkdir "$work"
work=$(CDPATH= cd -- "$work" && pwd)
fixtures=$(CDPATH= cd -- "$fixtures" && pwd)
: > "$work/results.tsv"
failed=0
for width in 32 64; do
    for kind in 0 1 2 3 4 5 6 7 8 9 10 11; do
        case $kind in
        0) label=direct ;;
        1) label=call4 ;;
        2) label=call_ref ;;
        3) label=entry_value_const ;;
        4) label=default_location ;;
        5) label=startx_endx ;;
        6) label=startx_length ;;
        7) label=call_ref_cross_cu ;;
        8) label=default_before_match ;;
        9) label=default_after_nonmatch ;;
        10) label=truncated_call_ref ;;
        11) label=truncated_default ;;
        esac
        log=$work/w$width-$label.log
        status=PASS
        exit_status=0
        "$gdb" -nx -nh -batch "$fixtures/limits-w$width-k$kind" \
            -ex 'set confirm off' -ex 'break *main' -ex run \
            -ex 'printf "VALUE=%d\n", variant_value' -ex continue > "$log" 2>&1 \
            || exit_status=$?
        [ "$exit_status" = 0 ] || status=FAIL
        grep -q 'VALUE=42' "$log" || status=FAIL
        grep -q 'exited normally' "$log" || status=FAIL
        case $kind in
        10|11)
            status=FAIL
            # A later successful -ex continue can mask the error's exit
            # status. Require the diagnostic and absence of a value/crash.
            if [ "$exit_status" -lt 128 ] \
                && grep -Ei 'Truncated|too few bytes' "$log" > /dev/null \
                && ! grep -Ei 'VALUE=42|internal-error|Segmentation fault' "$log" > /dev/null; then
                status=PASS
            fi
            ;;
        esac
        printf '%s\t%s\t%s\n' "$width" "$label" "$status" | tee -a "$work/results.tsv"
        [ "$status" != FAIL ] || failed=$((failed + 1))
    done
done
printf 'Failed checks: %s\n' "$failed"
[ "$failed" = 0 ]
