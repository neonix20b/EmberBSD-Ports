#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted production-body query/poll regression.
# Software model only: no GL driver, GPU, QEMU or guest execution.
set -eu
[ "$#" -eq 3 ] || { echo "Usage: $0 BASE_RENDERER FIXED_RENDERER NEW_ABSOLUTE_WORK" >&2; exit 2; }
base=$1 fixed=$2 work=$3
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "$base:$fixed:$work" in /*:/*:/*) ;; *) echo 'Absolute paths required' >&2; exit 2;; esac
hash() { shasum -a 256 "$1" | awk '{print $1}'; }
check() { [ "$(hash "$1")" = "$2" ] || { echo "SHA256 mismatch: $1" >&2; exit 1; }; }
check "$base/src/vrend/vrend_renderer.c" 91793e7be6d96329c96ac9e4fa5f9508bae872458749f8f6522bd246c3f35007
check "$base/src/virglrenderer.c" 8e50629afff52ef6556173e97ce6b960fea00282105d03896f0b7d0c32968152
check "$base/src/vrend/iov.c" 110e3a290262e7d412b74f8acf8a2b483143250e7a3bfae365380788d3dcee03
check "$base/src/virglrenderer.h" ecf1211dc64b84989785d9eed0b53cf20979f87480a4a8864da01f6493b984f3
check "$base/src/virgl_hw.h" 191ca5cea527949a29e9753b1e31d550f2fed922895d78dabc5c5c3585aa2ff7
check "$base/src/virgl_protocol.h" 094a6e2b210f1d3dd0f1ac254ed8820c1d889e57d2735c0c6194dbc94f3b1ac7
check "$base/src/mesa/util/list.h" b9a8fcb50769d3bfa32163b8fceff6c316de6b8d3dacec8f06ebebda926ac154
for path in src/vrend/vrend_renderer.c src/virglrenderer.c; do
    expected=$(awk -F '\t' -v path="$path" '$1=="output" && $2==path {print $3; n++} END {if(n!=1)exit 1}' "$recipe/renderer-files.tsv")
    check "$fixed/$path" "$expected"
done
mkdir "$work"
CC=$(command -v "${CC:-cc}")
case "$CC" in /*) ;; *) echo 'Compiler must resolve to an absolute path' >&2; exit 2;; esac
"$CC" --version > "$work/compiler.txt"
uname -a > "$work/platform.txt"
shasum -a 256 "$CC" "$0" "$recipe/query-poll-seams.h" "$recipe/query-poll-cases.h" \
    "$recipe/renderer-files.tsv" "$recipe/../tests/extract-lifecycle.awk" \
    "$recipe/../tests/extract-backing-shape.awk" > "$work/test-inputs-sha256.txt"
f() { awk -v name="$2" -f "$recipe/../tests/extract-lifecycle.awk" "$1"; }
shape() { awk -v kind=struct -v name="$2" -f "$recipe/../tests/extract-backing-shape.awk" "$1"; }
for variant in baseline bounds-only patched; do
    out=$work/$variant
    mkdir "$out"
    source=$base
    [ "$variant" = baseline ] || source=$fixed
    r=$source/src/vrend/vrend_renderer.c
    api=$source/src/virglrenderer.c
    # Original complete source copies retain their notices and identify every
    # extracted body. Unchanged headers/list/IOV implementation come from BASE.
    cp "$r" "$out/renderer-source.c"
    cp "$api" "$out/api-source.c"
    cp "$base/src/vrend/vrend_renderer.c" "$out/baseline-renderer-source.c"
    cp "$base/src/vrend/iov.c" "$out/iov-source.c"
    cp "$base/src/virglrenderer.h" "$base/src/virgl_hw.h" "$base/src/virgl_protocol.h" "$out/"
    cp "$base/src/mesa/util/list.h" "$out/query-list.h"
    cp "$recipe/query-poll-seams.h" "$recipe/query-poll-cases.h" "$out/"
    printf '%s\n' '#define VIRGL_VERSION_MAJOR 1' '#define VIRGL_VERSION_MINOR 3' '#define VIRGL_VERSION_MICRO 0' > "$out/virgl-version.h"
    shape "$r" vrend_fence > "$out/query-fence.inc"
    shape "$r" vrend_query > "$out/query-shape.inc"
    shape "$r" global_renderer_state > "$out/query-state.inc"
    shape "$api" global_state > "$out/query-api-state.inc"
    : > "$out/functions.inc"
    : > "$out/prototypes.inc"
    printf 'function\tsource\n' > "$out/selections.tsv"
    names='vrend_report_context_error_internal vrend_is_timer_query vrend_get_one_query_result vrend_update_oq_samples_multiplier vrend_check_query vrend_get_query_result vrend_destroy_query vrend_renderer_find_sub_ctx vrend_hw_switch_context_with_sub vrend_hw_switch_context vrend_finish_context_switch vrend_renderer_force_ctx_0 vrend_renderer_check_queries do_wait free_fence_locked vrend_free_fences need_fence_retire_signal_locked vrend_renderer_check_fences vrend_renderer_poll vrend_renderer_fini vrend_renderer_ember_classic_wait_init vrend_renderer_ember_classic_wait_status'
    [ "$variant" = baseline ] || names="vrend_query_buffer_fits $names"
    for name in $names; do
        input=$r
        # Causal intermediate: repaired bounds, original complete queue/fence
        # bodies. This isolates the poll error propagation from output bounds.
        if [ "$variant" = bounds-only ]; then
            case "$name" in vrend_renderer_check_queries|vrend_renderer_check_fences) input=$base/src/vrend/vrend_renderer.c;; esac
        fi
        f "$input" "$name" > "$out/$name.inc"
        printf '%s\t%s\n' "$name" "$input" >> "$out/selections.tsv"
        cat "$out/$name.inc" >> "$out/functions.inc"
    done
    for name in virgl_renderer_poll virgl_renderer_cleanup virgl_renderer_ember_classic_init_v1 virgl_renderer_ember_classic_wait_status_v1 virgl_renderer_ember_classic_poll_v1; do
        f "$api" "$name" > "$out/$name.inc"
        printf '%s\t%s\n' "$name" "$api" >> "$out/selections.tsv"
        cat "$out/$name.inc" >> "$out/functions.inc"
    done
    f "$base/src/vrend/iov.c" vrend_write_to_iovec > "$out/vrend_write_to_iovec.inc"
    printf '%s\t%s\n' vrend_write_to_iovec "$base/src/vrend/iov.c" >> "$out/selections.tsv"
    cat "$out/vrend_write_to_iovec.inc" >> "$out/functions.inc"
    for file in "$out"/vrend_*.inc "$out"/virgl_renderer_*.inc; do
        awk '/^\{/{print ";";exit} /\{/{sub(/\{.*/,";");print;exit}{print}' "$file" >> "$out/prototypes.inc"
    done
    printf '%s\n' '#include "query-poll-seams.h"' '#include "functions.inc"' '#include "query-poll-cases.h"' > "$out/query-poll.c"
    (cd "$out" && find . -type f -exec shasum -a 256 {} \;) > "$out/extracted-sha256.txt"
    for mode in plain sanitized; do
        set --
        [ "$variant" = baseline ] || set -- "$@" -DQUERY_HAS_BOUNDS
        [ "$mode" != sanitized ] || set -- "$@" -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
        "$CC" -std=gnu11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-parameter \
            "$@" -I"$out" "$out/query-poll.c" -o "$out/$mode" > "$out/$mode-compile.log" 2>&1 || { cat "$out/$mode-compile.log" >&2; exit 1; }
        status=0
        "$out/$mode" > "$out/$mode.log" 2>&1 || status=$?
        printf '%s\n' "$status" > "$out/$mode.status"
        if [ "$variant" = patched ]; then
            [ "$status" -eq 0 ] && grep -Fqx 'query poll: 226 checks, 0 failures' "$out/$mode.log" || { cat "$out/$mode.log" >&2; exit 1; }
        else
            [ "$status" -eq 1 ] && grep -Fq 'FAIL delayed query failure reaches checked poll' "$out/$mode.log" || { cat "$out/$mode.log" >&2; exit 1; }
            expected_failures=32
            [ "$variant" != bounds-only ] || expected_failures=28
            grep -Fqx "query poll: 226 checks, $expected_failures failures" "$out/$mode.log" || { cat "$out/$mode.log" >&2; exit 1; }
        fi
        grep -Fqx 'query controls: 66 checks, 0 failures' "$out/$mode.log" || { cat "$out/$mode.log" >&2; exit 1; }
        if grep -Eq 'ERROR: AddressSanitizer|runtime error:|LeakSanitizer' "$out/$mode.log"; then cat "$out/$mode.log" >&2; exit 1; fi
        printf '%s %s: ' "$variant" "$mode"
        tail -1 "$out/$mode.log"
    done
done
printf '%s\n' 'PASS: production query/poll software model, baseline and bounds-only RED, fixed GREEN, plain/ASan+UBSan. No GPU or guest qualification.'
