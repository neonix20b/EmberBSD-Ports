#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), distinguish entry state from live state.
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
failed=0
: > "$work/results.tsv"
check()
{
    label=$1 breakpoint=$2 variable=$3 expected=$4
    log=$work/w$width-$label.log
    exit_status=0
    "$gdb" -nx -nh -batch "$fixtures/entry-w$width" \
        -ex 'set confirm off' -ex "break *$breakpoint" -ex run \
        -ex 'printf "CURRENT=%ld,%ld,%ld,%ld\n", $x0, $x1, $x19, *(int *)&entry_cell' \
        -ex 'printf "TYPED=%lx,%lx\n", $x4, $v0.d.u[1]' \
        -ex "printf \"VALUE=%d\\n\", $variable" -ex continue > "$log" 2>&1 \
        || exit_status=$?
    status=PASS
    [ "$exit_status" -lt 128 ] || status=FAIL
    grep -q 'exited normally' "$log" || status=FAIL
    if [ "$breakpoint" = entry_stop ]; then
        grep -q 'CURRENT=100,9,77,99' "$log" || status=FAIL
        grep -q 'TYPED=63,0' "$log" || status=FAIL
    else
        grep -q 'CURRENT=40,2,39,42' "$log" || status=FAIL
        grep -q 'TYPED=422a0000,2a' "$log" || status=FAIL
    fi
    case $expected in
    value:*)
        grep -qx "VALUE=${expected#value:}" "$log" || status=FAIL ;;
    *)
        grep -Ei "$expected" "$log" > /dev/null || status=FAIL
        if grep -Eq '^VALUE=-?[0-9]' "$log"; then status=FAIL; fi ;;
    esac
    if grep -Ei 'internal-error|Segmentation fault|Assertion.*failed' "$log" > /dev/null; then status=FAIL; fi
    printf '%s\t%s\t%s\n' "$width" "$label" "$status" | tee -a "$work/results.tsv"
    [ "$status" != FAIL ] || failed=$((failed + 1))
}
for width in 32 64; do
    for variable in constant gnu_entry branch arithmetic nested isolated breg_value bregx_value registers nested_register data_value procedure typed_float typed_wide; do
        check "$variable" entry_stop "$variable" value:42
    done
    check restored_context entry_stop restored_context value:140
    check reg_value entry_stop reg_value value:40
    check live_typed_float entry_probe typed_float value:42
    check live_typed_wide entry_probe typed_wide value:42
    check live_memory entry_probe memory_value value:42
    check live_registers entry_probe registers value:42
    check memory_unavailable entry_stop memory_value 'entry-time memory is unavailable|optimized out|not available'
    check missing_register entry_stop missing_register 'Cannot find matching parameter|optimized out|not available'
    check frame_base entry_stop frame_base 'entry-time frame state is unavailable|optimized out|not available'
    check cfa_value entry_stop cfa_value 'entry-time frame state is unavailable|optimized out|not available'
    for variable in empty two_values pieces; do
        check "$variable" entry_stop "$variable" 'must produce exactly one value'
    done
    check borrowed_stack entry_stop borrowed_stack 'stack underflow'
    check truncated_block entry_stop truncated_block 'too few bytes'
    check overflowing_length entry_stop overflowing_length 'too few bytes'
    check truncated_type entry_stop truncated_type 'Truncated DWARF expression operand'
    check truncated_leb entry_stop truncated_leb 'ran off end of buffer'
    check truncated_fixed entry_stop truncated_fixed 'Truncated DWARF expression operand'
    check bad_branch entry_stop bad_branch 'DWARF expression branch out of range'
    check recursive entry_stop recursive 'Loop detected'
    check object_address entry_stop object_address 'DW_OP_push_object_address is not meaningful'
done
printf 'Failed entry-value checks: %s\n' "$failed"
[ "$failed" = 0 ]
