#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), DWARF agent-compiler recursion regression.
set -eu
[ "$#" = 3 ] || { echo "Usage: $0 GDB FIXTURES NEW_RESULTS" >&2; exit 2; }
gdb=$1 fixtures=$2 work=$3
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ]
[ -z "${LD_LIBRARY_PATH-}${LD_PRELOAD-}" ] || { echo 'Remove loader overrides.' >&2; exit 2; }
# An unpatched debugger can exhaust its stack on the negative cases. Keep
# that failure inside the test process, with no core file or unlimited CPU.
ulimit -c 0
ulimit -t 15
mkdir "$work"
work=$(CDPATH= cd -- "$work" && pwd)
fixtures=$(CDPATH= cd -- "$fixtures" && pwd)
: > "$work/results.tsv"
failed=0
for width in 32 64; do
    for kind in 0 1 2 7 12 13 14; do
        case $kind in
        0) label=direct ;;
        1) label=call4 ;;
        2) label=call_ref ;;
        7) label=call_ref_cross_cu ;;
        12) label=recursive_call2 ;;
        13) label=recursive_call4 ;;
        14) label=recursive_call_ref ;;
        esac
        log=$work/w$width-$label.log
        exit_status=0
        "$gdb" -nx -nh -batch "$fixtures/limits-w$width-k$kind" \
            -ex 'maintenance agent -at main, variant_value' > "$log" 2>&1 \
            || exit_status=$?
        status=FAIL
        case $kind in
        12|13|14)
            # This exact message originates in the AX compiler. A parser
            # or symbol-requirement-scanner rejection does not pass.
            if [ "$exit_status" -gt 0 ] && [ "$exit_status" -lt 128 ] \
                && grep -q 'DWARF agent expression recursion limit exceeded' "$log" \
                && ! grep -Ei 'internal-error|Segmentation fault' "$log" > /dev/null; then
                status=PASS
            fi
            ;;
        *)
            if [ "$exit_status" = 0 ] && grep -q 'const8 4[12]' "$log" \
                && grep -Eq '[[:space:]]end$' "$log"; then
                status=PASS
            fi
            if [ "$kind" = 7 ]; then
                grep -q 'const8 1' "$log" || status=FAIL
                grep -Eq '[[:space:]]add$' "$log" || status=FAIL
            fi
            ;;
        esac
        printf '%s\t%s\t%s\n' "$width" "$label" "$status" | tee -a "$work/results.tsv"
        [ "$status" = PASS ] || failed=$((failed + 1))
    done
done
printf 'Failed AX compiler checks: %s\n' "$failed"
[ "$failed" = 0 ]
