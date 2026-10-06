#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted production extraction and RED/GREEN regression.
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 ORIGINAL_ARCHIVE NEW_WORK" >&2; exit 2; }
archive=$1
work=$2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
expected=9bce3180e0911bee8f0cfa99e7581843a1a466c018b1547df455838c0a8430fd
if command -v sha256 >/dev/null 2>&1; then actual=$(sha256 -q "$archive");
else actual=$(shasum -a 256 "$archive" | awk '{print $1}'); fi
[ "$actual" = "$expected" ] || { echo 'Original archive SHA256 mismatch' >&2; exit 1; }
mkdir "$work"
work=$(CDPATH= cd -- "$work" && pwd)
mkdir "$work/original" "$work/patched"
tar -xzf "$archive" -C "$work/original" --strip-components=1
tar -xzf "$archive" -C "$work/patched" --strip-components=1
patch -f -d "$work/patched" -p1 -F 0 < "$recipe/patches/0001-descriptor-lifetime.patch"
for tree in original patched; do
    out=$work/$tree-test
    mkdir "$out"
    src=$work/$tree/Linux/driver/umd/src
    awk -v mode=status -f "$recipe/tests/extract.awk" "$src/common/device_base.h" > "$out/status.inc"
    for mode in members factory; do
        awk -v mode="$mode" -f "$recipe/tests/extract.awk" "$src/device/aipu/aipu.h" > "$out/$mode.inc"
    done
    for mode in lifetime tick; do
        awk -v mode="$mode" -f "$recipe/tests/extract.awk" "$src/device/aipu/aipu.cpp" > "$out/$mode.inc"
    done
    "${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -pthread -I"$out" \
        "$recipe/tests/lifetime.cc" -o "$out/lifetime"
done
# Every invocation has fresh real fd state. Original controls must fail for
# the observed production defect, not for compilation or fixture errors.
for test in initial zero-success zero-cap-failure zero-partition-failure \
    cap-failure partition-failure empty-cap success destructor zero-destructor tick-success tick-error open-failure; do
    if "$work/original-test/lifetime" "$test" > "$work/original-$test.log" 2>&1; then old=0; else old=$?; fi
    if [ "$test" = open-failure ] || [ "$test" = destructor ]; then
        [ "$old" -eq 0 ]
    else
        [ "$old" -eq 1 ]
        case "$test" in
            initial) diagnostic='header invalid descriptor sentinel' ;;
            zero-success|zero-destructor) diagnostic='valid open succeeds including fd zero' ;;
            zero-*-failure) diagnostic='query error preserved (including fd zero)' ;;
            cap-failure|partition-failure|empty-cap) diagnostic='unrelated reused fd survives destructor' ;;
            *) diagnostic='deinit invalidates descriptor' ;;
        esac
        grep -Fqx "FAIL: $diagnostic" "$work/original-$test.log"
    fi
    "$work/patched-test/lifetime" "$test" > "$work/patched-$test.log" 2>&1
    printf '%s original=%s patched=0\n' "$test" "$old"
done
echo 'PASS: actual production lifetime/factory/tick text; host fd contracts only'
