#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted complete-body extraction; no production substitution.
set -eu
mode=$1
work=$2
out=$3
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ ! -e "$out" ] || { echo 'Extraction directory already exists' >&2;exit 1; }
mkdir -p "$out"
f() { awk -v name="$2" -f "$recipe/tests/extract-lifecycle.awk" "$1"; }
shape() { awk -v kind="$2" -v name="$3" -f "$recipe/tests/extract-backing-shape.awk" "$1"; }
q=$work/qemu/lifecycle
r=$work/renderer-lifecycle
case "$mode" in
qemu)
h=$q/include/hw/virtio/virtio-gpu.h
v=$q/hw/display/virtio-gpu-virgl.c
shape "$h" struct virtio_gpu_ctrl_command > "$out/command.inc"
shape "$h" struct virtio_gpu_simple_resource > "$out/resource.inc"
shape "$v" enum virtio_gpu_classic_backing_state > "$out/ledger-shape.inc"
shape "$v" struct virtio_gpu_virgl_resource >> "$out/ledger-shape.inc"
shape "$h" struct VirtIOGPUGL > "$out/gl-shape.inc"
shape "$h" struct virtio_gpu_virgl_context_fence >> "$out/gl-shape.inc"
awk '/^typedef enum ClassicLifecycle /{a=1}a{print}a && /^} ClassicLifecycle;/{a=0;n++}END{if(n!=1)exit 1}' "$h" > "$out/state.inc"
: > "$out/protos.tmp"
: > "$out/functions.inc"
for n in detach_classic_backing release_classic_backing virtio_gpu_virgl_schedule_lifecycle virtio_gpu_virgl_close_admission virtio_gpu_virgl_cmdq_allowed virtio_gpu_virgl_request_fault virtio_gpu_virgl_request_reset virtio_gpu_virgl_terminal_response virtio_gpu_virgl_drain_commands virtio_gpu_virgl_revoke virtio_gpu_virgl_reset_resources virtio_gpu_virgl_lifecycle_bh virtio_gpu_virgl_lifecycle_unrealize virtio_gpu_virgl_classic_command virtio_gpu_virgl_dispatch_cmd virtio_gpu_virgl_process_cmd virgl_write_fence virgl_write_context_fence virtio_gpu_virgl_reset_async_fences virtio_gpu_virgl_async_fence_bh virtio_gpu_virgl_push_async_fence virgl_write_async_fence virgl_write_async_context_fence virtio_gpu_print_stats virtio_gpu_fence_poll virtio_gpu_virgl_fence_poll virtio_gpu_virgl_reset_scanout virtio_gpu_virgl_lifecycle_realize virtio_gpu_virgl_init virgl_cmd_context_create virgl_cmd_get_capset virtio_gpu_virgl_resume_cmdq_bh virtio_gpu_virgl_add_capset virtio_gpu_virgl_get_capsets;do
 f "$v" "$n" > "$out/$n.inc"
 # Forward declarations mechanically preserve complete production signatures.
 awk '/^\{/{print ";";exit} /\{/{sub(/\{.*/,";");print;exit}{print}' "$out/$n.inc" >> "$out/protos.tmp"
 cat "$out/$n.inc" >> "$out/functions.inc"
done
for n in virtio_gpu_process_cmdq virtio_gpu_reset_bh virtio_gpu_reset;do f "$q/hw/display/virtio-gpu.c" "$n" >> "$out/functions.inc"; done
for n in virtio_gpu_gl_reset virtio_gpu_gl_flushed virtio_gpu_gl_handle_ctrl virtio_gpu_gl_update_cursor_data virtio_gpu_gl_device_realize;do f "$q/hw/display/virtio-gpu-gl.c" "$n" >> "$out/functions.inc";done
mv "$out/protos.tmp" "$out/protos.inc"
awk '/^static const struct virgl_renderer_callbacks virtio_gpu_3d_cbs_default =/{a=1}a{print}a&&/^};/{a=0;n++}END{if(n!=1)exit 1}' "$v" > "$out/defaults.inc"
awk '/^#define VIRTIO_GPU_FILL_CMD\(out\)/{a=1}a{print;if(/while \(0\)/){a=0;n++}}END{if(n!=1)exit 1}' "$h" > "$out/fill.inc"
printf '%s\n' '#define VIRGL_VERSION_MAJOR 1' '#define VIRGL_VERSION_MINOR 3' '#define VIRGL_VERSION_MICRO 0' > "$out/virgl-version.h"
# Token identities are a wire/feature seam, not a substitute decoder table.
rg -o 'VIRTIO_GPU_(CMD_[A-Z0-9_]+|CAPSET_[A-Z0-9_]+)' "$out/functions.inc" --no-filename | sort -u | awk '{print "#define " $0 " " ++n}' > "$out/tokens.inc"

;;
renderer)
if [ "${4:-patched}" = baseline ];then cp "$work/renderer-extra-original/src/virglrenderer.h" "$out/";r=$work/renderer;winsys=$work/renderer-extra-original/src/vrend/vrend_winsys.c;else winsys=$r/src/vrend/vrend_winsys.c;fi
: > "$out/renderer-functions.inc"
for n in vrend_renderer_check_queries vrend_renderer_check_fences vrend_renderer_poll;do f "$r/src/vrend/vrend_renderer.c" "$n" >> "$out/renderer-functions.inc";done
f "$r/src/virglrenderer.c" virgl_renderer_poll >> "$out/renderer-functions.inc"
if [ "${4:-patched}" != baseline ];then f "$r/src/virglrenderer.c" virgl_renderer_ember_classic_init_v1 >> "$out/renderer-functions.inc";fi
f "$work/renderer-extra-original/src/vrend/vrend_winsys_egl.c" virgl_egl_init_external > "$out/winsys-functions.inc"
for n in vrend_winsys_init_external vrend_winsys_cleanup;do f "$winsys" "$n" >> "$out/winsys-functions.inc";done
printf '%s\n' '#define VIRGL_VERSION_MAJOR 1' '#define VIRGL_VERSION_MINOR 3' '#define VIRGL_VERSION_MICRO 0' > "$out/virgl-version.h"
awk -v kind=struct -v name=global_state -f $recipe/tests/extract-backing-shape.awk "$r/src/virglrenderer.c" > "$out/renderer-state.inc"
awk '/^#define VREND_USE_|^#define VREND_NATIVE_SHARE_TEXTURE/{print}' "$r/src/vrend/vrend_renderer.h" > "$out/renderer-flags.inc"
f "$r/src/virglrenderer.c" virgl_renderer_init > "$out/renderer-init.inc"

;;
reset)
 q=$work/qemu/patched
 v=$q/hw/display/virtio-gpu-virgl.c
 shape "$v" enum virtio_gpu_classic_backing_state > "$out/red-shape.inc"
 shape "$v" struct virtio_gpu_virgl_resource >> "$out/red-shape.inc"
 : > "$out/red-destroy.inc"
 for n in detach_classic_backing release_classic_backing virtio_gpu_virgl_resource_destroy;do f "$v" "$n" >> "$out/red-destroy.inc";done
 : > "$out/reset-red.inc"
 for n in virtio_gpu_reset_bh virtio_gpu_reset;do f "$q/hw/display/virtio-gpu.c" "$n" >> "$out/reset-red.inc";done
 f "$q/hw/display/virtio-gpu-gl.c" virtio_gpu_gl_reset >> "$out/reset-red.inc"
 ;;
backing)
 # Reuse accepted C8c1 test seam and the same actual production selections.
 q=$work/qemu/patched
 v=$q/hw/display/virtio-gpu-virgl.c
 src=$r/src
 printf '%s\n' '#define HAVE_SYS_UIO_H 1' > "$out/config.h"
 shape "$v" enum virtio_gpu_classic_backing_state > "$out/qemu-shape.inc"
 shape "$v" struct virtio_gpu_virgl_resource >> "$out/qemu-shape.inc"
 shape "$v" struct virtio_gpu_virgl_hostmem_region >> "$out/qemu-shape.inc"
 sed -n '1,13p' "$v" > "$out/qemu.inc"
 for n in virtio_gpu_virgl_find_resource detach_classic_backing release_classic_backing to_hostmem_region virtio_gpu_virgl_finish_unmap virtio_gpu_virgl_unmap_resource_blob virtio_gpu_virgl_destroy_hostmem_region virtio_gpu_virgl_resource_destroy virgl_create_resource_error virgl_cmd_create_resource_2d virgl_cmd_create_resource_3d virgl_cmd_resource_unref virgl_resource_attach_backing virgl_resource_detach_backing virgl_cmd_resource_create_blob;do f "$v" "$n" >> "$out/qemu.inc";done
 : > "$out/mapping.inc"
 for n in virtio_gpu_create_mapping_iov virtio_gpu_cleanup_mapping_iov;do f "$q/hw/display/virtio-gpu.c" "$n" >> "$out/mapping.inc";done
 : > "$out/base-cleanup.inc"
 for n in virtio_gpu_cleanup_mapping virtio_gpu_resource_destroy;do f "$q/hw/display/virtio-gpu.c" "$n" >> "$out/base-cleanup.inc";done
 awk '/^#define VIRTIO_GPU_FILL_CMD\(out\)/{a=1}a{print;if(/while \(0\)/){a=0;n++}}END{if(n!=1)exit 1}' "$q/include/hw/virtio/virtio-gpu.h" > "$out/fill.inc"
 sed -n '1,23p' "$src/vrend/vrend_renderer.c" > "$out/pipe.inc"
 for n in vrend_pipe_resource_unref vrend_pipe_resource_attach_iov vrend_pipe_resource_detach_iov;do f "$src/vrend/vrend_renderer.c" "$n" >> "$out/pipe.inc";done
 sed -n '1,23p' "$src/virgl_resource.c" > "$out/resource.inc"
 for n in virgl_resource_destroy_func virgl_resource_lookup virgl_resource_remove virgl_resource_attach_iov virgl_resource_detach_iov;do f "$src/virgl_resource.c" "$n" >> "$out/resource.inc";done
 sed -n '1,23p' "$src/virglrenderer.c" > "$out/api.inc"
 for n in virgl_renderer_resource_attach_iov virgl_renderer_resource_detach_iov virgl_renderer_resource_unref;do f "$src/virglrenderer.c" "$n" >> "$out/api.inc";done
 f "$src/vrend/vrend_renderer.h" vrend_resource_reference > "$out/reference.inc"
 f "$src/vrend/vrend_renderer.c" vrend_renderer_resource_destroy > "$out/renderer-destroy.inc"
 awk '/^#define VREND_STORAGE_/{print}' "$src/vrend/vrend_renderer.h" > "$out/storage.inc"
 : > "$out/pipe-reference.inc"
 for n in pipe_is_referenced pipe_reference_described pipe_reference;do f "$src/gallium/auxiliary/util/u_inlines.h" "$n" >> "$out/pipe-reference.inc";done
 shape "$src/vrend/vrend_renderer.c" struct vrend_query > "$out/query-shape.inc"
 shape "$src/virgl_protocol.h" struct virgl_host_query_state >> "$out/query-shape.inc"
 : > "$out/query.inc"
 for n in vrend_create_query vrend_check_query vrend_destroy_query;do f "$src/vrend/vrend_renderer.c" "$n" >> "$out/query.inc";done
 awk '{s=$0;while(match(s,/GL_[A-Z_0-9]+|feat_[a-z_0-9]+|PIPE_QUERY_[A-Z_0-9]+|VIRGL_ERROR_[A-Z_0-9]+|VIRGL_OBJECT_[A-Z_0-9]+/)){print substr(s,RSTART,RLENGTH);s=substr(s,RSTART+RLENGTH)}}' "$out/query.inc" | sort -u | awk '{print "#define " $0 " " ++n}' > "$out/query-defs.inc"
 h=$work/qemu/lifecycle/include/hw/virtio/virtio-gpu.h
 awk '/^typedef enum ClassicLifecycle /{a=1}a{print}a && /^} ClassicLifecycle;/{a=0;n++}END{if(n!=1)exit 1}' "$h" > "$out/state.inc"
 f "$work/qemu/lifecycle/hw/display/virtio-gpu-virgl.c" virtio_gpu_virgl_revoke > "$out/revoke.inc"
 ruby "$recipe/tests/lifecycle-seams.rb" backing "$recipe/tests/backing.c" > "$out/backing.c"
 ;;
*) echo 'Unknown extraction mode' >&2;exit 2;;
esac
find "$out" -name '*.inc' -type f -exec shasum -a 256 {} \; > "$out/extracted-sha256.txt"
