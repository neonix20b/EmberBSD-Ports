#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted compiled production-source RED/GREEN gate.
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 ORIGINAL_UTM_ARCHIVE NEW_ABSOLUTE_WORK" >&2; exit 2; }
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$2
sh "$recipe/prepare.sh" "$1" "$work"
"${CC:-cc}" --version > "$work/compiler.txt"
"${PYTHON:-python3}" --version > "$work/python.txt" 2>&1
"${PYTHON:-python3}" -c 'import yaml; print(yaml.__version__); print(yaml.__file__)' > "$work/pyyaml.txt"
for tree in original patched; do
    src=$work/$tree/src
    out=$work/$tree-test
    mkdir "$out"
    cat > "$out/config.h" <<'CONFIG'
#define HAVE_SYS_UIO_H 1
#if !defined(__BYTE_ORDER__) || !defined(__ORDER_LITTLE_ENDIAN__) || !defined(__ORDER_BIG_ENDIAN__)
#error Compiler byte order definitions required
#elif __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define UTIL_ARCH_LITTLE_ENDIAN 1
#define UTIL_ARCH_BIG_ENDIAN 0
#elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define UTIL_ARCH_LITTLE_ENDIAN 0
#define UTIL_ARCH_BIG_ENDIAN 1
#else
#error Unsupported host byte order
#endif
CONFIG
    # These are unmodified upstream generators, requiring Python and PyYAML.
    PYTHONDONTWRITEBYTECODE=1 "${PYTHON:-python3}" \
        "$src/gallium/auxiliary/util/u_format_table.py" \
        "$src/gallium/auxiliary/util/u_format.yaml" --enums > "$out/u_format_gen.h"
    PYTHONDONTWRITEBYTECODE=1 "${PYTHON:-python3}" \
        "$src/gallium/auxiliary/util/u_format_table.py" \
        "$src/gallium/auxiliary/util/u_format.yaml" > "$out/u_format_table.c"
    awk -f "$recipe/tests/extract.awk" "$src/vrend/vrend_renderer.c" > "$out/renderer.inc"
    for mode in plain sanitized; do
        set --
        if [ "$mode" = sanitized ]; then
            set -- -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
        fi
        "${CC:-cc}" -std=c11 -Wall -Wextra -Werror "$@" -include "$out/config.h" \
            -I"$out" -I"$src" -I"$src/gallium/include" -I"$src/gallium/auxiliary" \
            -I"$src/gallium/auxiliary/util" -I"$src/mesa" -I"$src/mesa/compat" \
            -I"$src/mesa/pipe" -I"$src/mesa/util" -I"$src/vrend" \
            "$recipe/tests/bounds.c" "$out/u_format_table.c" "$src/vrend/iov.c" \
            -o "$out/bounds-$mode" > "$out/compile-$mode.log" 2>&1
    done
done
for mode in plain sanitized; do
    for tree in original patched; do
        if "$work/$tree-test/bounds-$mode" > "$work/$tree-$mode.log" 2>&1; then status=0; else status=$?; fi
        printf '%s\n' "$status" > "$work/$tree-$mode.status"
        if [ "$tree" = original ]; then
            [ "$status" -eq 1 ]
            [ "$(grep -c '^FAIL:' "$work/$tree-$mode.log")" -eq 5 ]
            for name in span-above-4GiB-short-backing iov-above-4GiB-offset \
                default-layer-above-UINT32_MAX explicit-layer-min-above-UINT32_MAX \
                large-iov-short-transfer; do
                grep -q "^FAIL: $name " "$work/$tree-$mode.log"
            done
            grep -Fqx '23 cases, 5 failed' "$work/$tree-$mode.log"
        else
            [ "$status" -eq 0 ]
            grep -Fqx '23 cases, 0 failed' "$work/$tree-$mode.log"
            "$work/$tree-test/bounds-$mode" limits > "$work/limits-$mode.log" 2>&1
        fi
    done
    printf '%s: BASE compiled RED (5 named truncations); patched GREEN (23 cases)\n' "$mode"
done
# Extraction is strict; absent, duplicate and truncated functions must fail.
header=$work/original/src/vrend/vrend_renderer.c
cat "$header" "$header" > "$work/duplicate.c"
sed -n '1,9410p' "$header" > "$work/truncated.c"
for input in /dev/null "$work/duplicate.c" "$work/truncated.c"; do
    if awk -f "$recipe/tests/extract.awk" "$input" > "$work/rejected.inc" 2> "$work/extraction-rejection.log"; then
        echo 'Unexpected acceptance of malformed renderer extraction' >&2; exit 1
    fi
    grep -Fq 'Unexpected renderer extraction shape' "$work/extraction-rejection.log"
done
printf '%s\n' 'PASS: actual format table, size helpers, renderer bounds and IOV sum; no GL/copy/runtime claim.'
