#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted production getter RED/GREEN regression.
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 ORIGINAL_ARCHIVE NEW_WORK" >&2; exit 2; }
archive=$1
work=$2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sanitizers=${CORE_TEST_SANITIZERS:-0}
case "$sanitizers" in 0|1) ;; *) echo 'CORE_TEST_SANITIZERS must be 0 or 1' >&2; exit 2 ;; esac
expected=9bce3180e0911bee8f0cfa99e7581843a1a466c018b1547df455838c0a8430fd
if command -v sha256 >/dev/null 2>&1; then actual=$(sha256 -q "$archive");
else actual=$(shasum -a 256 "$archive" | awk '{print $1}'); fi
[ "$actual" = "$expected" ] || { echo 'Original archive SHA256 mismatch' >&2; exit 1; }
mkdir "$work"
work=$(CDPATH= cd -- "$work" && pwd)
mkdir "$work/original" "$work/patched"
tar -xzf "$archive" -C "$work/original" --strip-components=1
tar -xzf "$archive" -C "$work/patched" --strip-components=1
for patchname in 0001-descriptor-lifetime 0002-core-count-bounds; do
    patch -f -N -F 0 -d "$work/patched" -p1 < "$recipe/patches/$patchname.patch"
done

for tree in original patched; do
    out=$work/$tree-test
    mkdir "$out"
    src=$work/$tree/Linux/driver
    header=$src/umd/src/common/device_base.h
    awk -v mode=status -f "$recipe/tests/extract.awk" "$header" > "$out/status.inc"
    for mode in getter members; do
        awk -v mode="$mode" -f "$recipe/tests/extract-core-count.awk" "$header" > "$out/$mode.inc"
    done
    awk -v mode=capability -f "$recipe/tests/extract-core-count.awk" \
        "$src/kmd/armchina-npu/include/armchina_aipu.h" > "$out/capability.inc"
    for sim in 0 1; do
        # Extra compiler/linker flags are deliberately shell words, as in make.
        # The required warnings and sanitizer recovery policy remain explicit.
        "${CXX:-c++}" ${CORE_TEST_CXXFLAGS:-} -std=c++17 -Wall -Wextra -Werror \
            -DSIMULATION="$sim" -I"$out" "$recipe/tests/core-count.cc" -o "$out/core-$sim"
        if [ "$sanitizers" -eq 1 ]; then
            "${CXX:-c++}" ${CORE_TEST_CXXFLAGS:-} -std=c++17 -Wall -Wextra -Werror \
                -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer \
                -fstrict-flex-arrays=3 \
                -DSIMULATION="$sim" -I"$out" "$recipe/tests/core-count.cc" -o "$out/core-sanitized-$sim"
        fi
    done
done

run_green()
{
    label=$1
    shift
    if "$@" > "$work/patched-$label.log" 2>&1; then result=0; else result=$?; fi
    printf '%s\n' "$result" > "$work/patched-$label.status"
    [ "$result" -eq 0 ]
}

for sim in 0 1; do
    if "$work/original-test/core-$sim" > "$work/original-$sim.log" 2>&1; then old=0; else old=$?; fi
    printf '%s\n' "$old" > "$work/original-$sim.status"
    [ "$old" -eq 1 ]
    failures=4
    if [ "$sim" -eq 0 ]; then failures=6; fi
    [ "$(grep -c '^FAIL:' "$work/original-$sim.log")" -eq "$failures" ]
    for name in partition-equal two-partition-equal; do
        grep -Fqx "FAIL: $name threw out_of_range" "$work/original-$sim.log"
    done
    for name in cluster-equal two-cluster-equal; do
        grep -q "^FAIL: $name status=" "$work/original-$sim.log"
    done
    if [ "$sim" -eq 0 ]; then
        grep -Fqx 'FAIL: empty-cluster threw out_of_range' "$work/original-$sim.log"
        grep -q '^FAIL: mixed-branch-control status=' "$work/original-$sim.log"
    fi
    grep -Fqx "SIMULATION=$sim: 28 cases, $failures failed" "$work/original-$sim.log"

    # This isolated sanitizer run proves the real fixed-array bound separately
    # from deterministic logical-count REDs. A compiler/harness error is not RED.
    if [ "$sanitizers" -eq 1 ]; then
        if "$work/original-test/core-sanitized-$sim" maximum-equal \
            > "$work/original-maximum-$sim.log" 2>&1; then old=0; else old=$?; fi
        printf '%s\n' "$old" > "$work/original-maximum-$sim.status"
        [ "$old" -ne 0 ]
        grep -q 'index 8 out of bounds' "$work/original-maximum-$sim.log"
        run_green "core-sanitized-$sim" "$work/patched-test/core-sanitized-$sim"
        run_green "core-sanitized-maximum-$sim" "$work/patched-test/core-sanitized-$sim" maximum-equal
        printf 'SIMULATION=%s maximum UBSan RED; ASan/UBSan=29 PASS\n' "$sim"
    else
        printf 'SKIP: SIMULATION=%s original maximum-bound sanitizer proof (CORE_TEST_SANITIZERS=0)\n' "$sim"
    fi
    run_green "core-$sim" "$work/patched-test/core-$sim"
    run_green "core-maximum-$sim" "$work/patched-test/core-$sim" maximum-equal
    printf 'SIMULATION=%s original=%s named failures; patched=29 PASS\n' "$sim" "$failures"
done

# Verify extraction refuses absent, duplicate and truncated production input.
header=$work/original/Linux/driver/umd/src/common/device_base.h
cat "$header" "$header" > "$work/duplicate.h"
sed -n '1,310p' "$header" > "$work/truncated.h"
for input in /dev/null "$work/duplicate.h" "$work/truncated.h"; do
    if awk -v mode=getter -f "$recipe/tests/extract-core-count.awk" "$input" \
        > "$work/rejected.inc" 2> "$work/extraction-rejection.log"; then
        echo 'Unexpected acceptance of malformed getter extraction' >&2
        exit 1
    fi
    grep -Fq 'Unexpected production extraction shape: getter' "$work/extraction-rejection.log"
done
for mode in members capability; do
    if awk -v mode="$mode" -f "$recipe/tests/extract-core-count.awk" /dev/null \
        > "$work/rejected.inc" 2> "$work/extraction-rejection.log"; then exit 1; fi
done
echo 'PASS: production core-count/status/capability text; no SDK or native NPU validation'
