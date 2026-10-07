#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted actual-function causal CREATE regression gate.
set -eu
[ "$#" -eq 3 ] || { echo "Usage: $0 ORIGINAL_RENDERER_ARCHIVE PINNED_RAW_INPUT_DIR NEW_ABSOLUTE_WORK" >&2; exit 2; }
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$3
case "${CREATE_SEAMS:-all}" in
all) seams='qemu renderer metal gbm combined' ;;
qemu) seams=qemu ;;
*) echo 'CREATE_SEAMS must be all or qemu' >&2; exit 2 ;;
esac
if [ -n "${GLIB_LIBRARY:-}" ]; then
    case "$GLIB_LIBRARY" in /*) ;; *) echo 'GLIB_LIBRARY must be absolute' >&2; exit 2 ;; esac
    [ -f "$GLIB_LIBRARY" ] || { echo 'Existing GLIB_LIBRARY missing' >&2; exit 2; }
fi
sh "$recipe/prepare-create.sh" "$1" "$2" "$work"
"${CC:-cc}" --version > "$work/compiler.txt"
extract() { awk -v name="$2" -f "$recipe/tests/extract-create.awk" "$1"; }
# One compiler worker. Source baselines already include the unchanged IOV patch.
for tree in baseline patched; do
    if [ "$tree" = baseline ]; then renderer=$work/renderer/patched; qemu=$work/qemu/original;
    else renderer=$work/renderer/create-patched; qemu=$work/qemu/patched; fi
    out=$work/$tree-test
    mkdir "$out"
    src=$renderer/src
    # Preserve complete original source notices in extracted compilation inputs.
    sed -n '1,13p' "$qemu/hw/display/virtio-gpu-virgl.c" > "$out/qemu.inc"
    if [ "$tree" = patched ]; then extract "$qemu/hw/display/virtio-gpu-virgl.c" virgl_create_resource_error >> "$out/qemu.inc"; fi
    for name in virtio_gpu_virgl_find_resource virgl_cmd_create_resource_2d virgl_cmd_create_resource_3d virgl_cmd_resource_unref virtio_gpu_virgl_process_cmd virgl_write_fence virgl_write_context_fence; do
        extract "$qemu/hw/display/virtio-gpu-virgl.c" "$name" >> "$out/qemu.inc"
    done
    awk '/^#define VIRTIO_GPU_FILL_CMD\(out\)/ { hits++; active=1 } active { print; if(/while \(0\)/) {active=0;done++} } END {if(hits!=1 || active || done!=1) exit 1}' "$qemu/include/hw/virtio/virtio-gpu.h" > "$out/fill.inc"
    sed -n '1,13p' "$qemu/hw/display/virtio-gpu.c" > "$out/response.inc"
    for name in virtio_gpu_ctrl_response virtio_gpu_ctrl_response_nodata; do extract "$qemu/hw/display/virtio-gpu.c" "$name" >> "$out/response.inc"; done
    extract "$qemu/hw/display/virtio-gpu.c" virtio_gpu_process_cmdq > "$out/queue.inc"
    sed -n '1,23p' "$src/vrend/vrend_renderer.c" > "$out/renderer.inc"
    for name in check_resource_valid vrend_create_buffer vrend_resource_alloc_buffer vrend_renderer_resource_copy_args vrend_resource_d3d_init vrend_resource_metal_init vrend_resource_gbm_init vrend_resource_alloc_texture vrend_resource_create vrend_renderer_resource_create vrend_renderer_resource_destroy vrend_pipe_resource_unref vrend_renderer_resource_get_map_info; do
        extract "$src/vrend/vrend_renderer.c" "$name" >> "$out/renderer.inc"
    done
    sed -n '1,23p' "$src/virgl_resource.c" > "$out/resource.inc"
    for name in virgl_resource_destroy_func virgl_resource_create virgl_resource_create_from_pipe virgl_resource_remove virgl_resource_lookup; do extract "$src/virgl_resource.c" "$name" >> "$out/resource.inc"; done
    sed -n '1,23p' "$src/virglrenderer.c" > "$out/api.inc"
    for name in virgl_renderer_resource_create_internal virgl_renderer_resource_create; do extract "$src/virglrenderer.c" "$name" >> "$out/api.inc"; done
    awk '/^struct vrend_renderer_resource_create_args \{/ {active=1;hits++} active {print;if(/^};/){active=0;done++}} END{if(hits!=1 || active || done!=1)exit 1}' "$src/vrend/vrend_renderer.h" > "$out/vrend-args.inc"
    awk '/^#define VREND_STORAGE_|^#define VIRGL_TEXTURE_/ {print}' "$src/vrend/vrend_renderer.h" > "$out/storage.inc"
    awk '/^enum pipe_texture_target$|^enum pipe_error \{/ {active=1;hits++} active {print;if(/^};/){active=0;done++}} END{if(hits!=2 || active || done!=2)exit 1}' "$src/gallium/include/pipe/p_defines.h" > "$out/pipe.inc"
    # These four source YAML aliases normally come from the upstream generator.
    # Extract only the simple named alias pairs required by this GL-free seam.
    awk '/^- name: / {format=$3} /^  alias: (NV12|NV21|YV12|P010)$/ {print "#define VIRGL_FORMAT_" $2 " VIRGL_FORMAT_" format; hits++} END {if(hits!=4)exit 1}' "$src/gallium/auxiliary/util/u_format.yaml" > "$out/format-alias.inc"
    # Generate only external seam constants from exact tokens in selected source.
    # Values carry no GL behavior; equal texture-buffer aliases are retained.
    awk '{s=$0;while(match(s,/GL_[A-Z_0-9]+|feat_[a-z_0-9]+/)){print substr(s,RSTART,RLENGTH);s=substr(s,RSTART+RLENGTH)}}' "$out/renderer.inc" | sort -u | awk '
    $0 == "GL_NO_ERROR" {print "#define GL_NO_ERROR 0"; next}
    $0 == "GL_TEXTURE_BUFFER_EXT" {print "#define GL_TEXTURE_BUFFER_EXT GL_TEXTURE_BUFFER"; next}
    {print "#define " $0 " " ++value+1000}
    ' > "$out/gl-defs.inc"
    printf '%s\n' '#define VIRGL_VERSION_MAJOR 1' '#define VIRGL_VERSION_MINOR 3' '#define VIRGL_VERSION_PATCH 0' > "$out/virgl-version.h"
    for mode in plain sanitized; do
        for seam in $seams; do
            set --
            if [ "$mode" = sanitized ]; then set -- "$@" -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer; fi
            if [ "$seam" = metal ]; then set -- "$@" -DENABLE_METAL -DHAVE_EPOXY_EGL_H; fi
            if [ "$seam" = gbm ]; then set -- "$@" -DENABLE_GBM -DENABLE_GBM_ALLOCATION -DHAVE_EPOXY_EGL_H; fi
            if [ "$seam" = combined ]; then set -- "$@" -DCREATE_INTEGRATED; fi
            case "$seam" in qemu|combined)
                if [ -n "${GLIB_LIBRARY:-}" ]; then set -- "$@" -DCREATE_GLIB_ALLOCATOR "$GLIB_LIBRARY"; fi ;;
            esac
            if [ "$seam" = qemu ]; then harness=create-qemu.c; else harness=create-renderer.c; fi
            "${CC:-cc}" -std=c11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-variable "$@" -I"$out" -I"$src" -I"$src/gallium/include" -I"$recipe/tests" \
                "$recipe/tests/$harness" -lm -o "$out/$seam-$mode" > "$out/compile-$seam-$mode.log" 2>&1
        done
    done
done
for mode in plain sanitized; do
    for seam in $seams; do
        for tree in baseline patched; do
            if "$work/$tree-test/$seam-$mode" > "$work/$tree-$seam-$mode.log" 2>&1; then status=0; else status=$?; fi
            printf '%s\n' "$status" > "$work/$tree-$seam-$mode.status"
            if [ "$tree" = baseline ]; then
                [ "$status" -eq 1 ]
                case "$seam" in
                qemu)
                    for defect in 'renderer failure reaches one error response' 'failed CREATE unpublished wrapper freed once' 'short complete-header CREATE rejected' 'wrapper OOM normally completes without renderer or abort'; do
                        grep -Fq "FAIL: $defect" "$work/$tree-$seam-$mode.log"
                    done ;;
                renderer|metal|gbm)
                    grep -Fq 'FAIL: actual texture failure destroys GL allocation with binding cleared' "$work/$tree-$seam-$mode.log"
                    if [ "$seam" != renderer ]; then grep -Fq 'FAIL: owned native GL/EGL/Metal/GBM failure fully destroyed' "$work/$tree-$seam-$mode.log"; fi ;;
                combined)
                    grep -Fq 'FAIL: combined rejection reaches guest without ghost resource' "$work/$tree-$seam-$mode.log"
                    grep -Fq 'FAIL: combined failure conserves ownership without second renderer unref' "$work/$tree-$seam-$mode.log" ;;
                esac
            else [ "$status" -eq 0 ]; fi
            if grep -E 'ERROR: AddressSanitizer|runtime error:|LeakSanitizer' "$work/$tree-$seam-$mode.log"; then exit 1; fi
        done
        printf '%s\n' "$seam/$mode: compiled baseline RED; patched GREEN"
    done
done
printf '%s\n' 'PASS: reported CREATE publication/unwind contracts; GL/native/transport seams only, no full QEMU/host or acceleration claim.'
