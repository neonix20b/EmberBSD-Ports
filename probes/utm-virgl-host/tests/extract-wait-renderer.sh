#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
set -eu
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$1 out=$2 variant=$3
[ ! -e "$out" ] || exit 2
mkdir -p "$out"
r=$work/renderer-lifecycle;egl=$work/wait-original/src/vrend/vrend_winsys_egl.c
[ "$variant" = baseline ] || { r=$work/renderer-wait;egl=$r/src/vrend/vrend_winsys_egl.c; }
f(){ awk -v name="$2" -f "$recipe/tests/extract-lifecycle.awk" "$1"; }
shape(){ awk -v kind=struct -v name="$2" -f "$recipe/tests/extract-backing-shape.awk" "$1"; }
cp "$r/src/virglrenderer.h" "$out/"
printf '%s\n' '#define VIRGL_VERSION_MAJOR 1' '#define VIRGL_VERSION_MINOR 3' '#define VIRGL_VERSION_MICRO 0' > "$out/virgl-version.h"
cp "$work/wait-original/src/mesa/util/list.h" "$out/wait-list.h"
shape "$r/src/vrend/vrend_renderer.c" vrend_fence > "$out/wait-fence.inc"
shape "$r/src/vrend/vrend_renderer.c" global_renderer_state > "$out/wait-state.inc"
shape "$r/src/virglrenderer.c" global_state > "$out/wait-api-state.inc"
: > "$out/wait-egl.inc"
for n in client_wait_fence virgl_egl_client_wait_fence;do f "$egl" "$n" >> "$out/wait-egl.inc";done
: > "$out/wait-renderer.inc"
if [ "$variant" != baseline ];then for n in vrend_renderer_ember_classic_wait_init vrend_renderer_ember_classic_wait_status;do f "$r/src/vrend/vrend_renderer.c" "$n" >> "$out/wait-renderer.inc";done;fi
for n in do_wait free_fence_locked vrend_free_fences need_fence_retire_signal_locked vrend_renderer_check_fences vrend_renderer_poll vrend_renderer_fini;do f "$r/src/vrend/vrend_renderer.c" "$n" >> "$out/wait-renderer.inc";done
f "$work/renderer-extra-original/src/vrend/vrend_decode.c" vrend_decode_ctx_retire_fences > "$out/wait-context.inc"
f "$r/src/virglrenderer.c" virgl_renderer_context_poll >> "$out/wait-context.inc"
: > "$out/wait-api.inc"
for n in virgl_renderer_poll virgl_renderer_cleanup virgl_renderer_ember_classic_init_v1;do f "$r/src/virglrenderer.c" "$n" >> "$out/wait-api.inc";done
if [ "$variant" != baseline ];then for n in virgl_renderer_ember_classic_wait_status_v1 virgl_renderer_ember_classic_poll_v1;do f "$r/src/virglrenderer.c" "$n" >> "$out/wait-api.inc";done;fi
cp "$recipe/tests/wait-renderer-seams.h" "$recipe/tests/wait-renderer.c" "$out/"
