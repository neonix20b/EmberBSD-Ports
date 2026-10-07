#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted actual-function backing ledger causal gate.
set -eu
[ "$#" -eq 3 ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$3
sh "$recipe/prepare-backing.sh" "$1" "$2" "$work"
"${CC:-cc}" --version > "$work/compiler.txt"
extract() { awk -v name="$2" -f "$recipe/tests/extract-create.awk" "$1"; }
shape() { awk -v kind="$2" -v name="$3" -f "$recipe/tests/extract-backing-shape.awk" "$1"; }
src=$work/renderer/src
for tree in baseline patched mutant; do
 if [ "$tree" = baseline ]; then qemu=$work/qemu/baseline; else qemu=$work/qemu/patched; fi
 out=$work/$tree-test;mkdir "$out"
 printf '%s\n' '#define HAVE_SYS_UIO_H 1' > "$out/config.h"
 virgl=$qemu/hw/display/virtio-gpu-virgl.c
 if [ "$tree" != baseline ]; then shape "$virgl" enum virtio_gpu_classic_backing_state > "$out/qemu-shape.inc";else : > "$out/qemu-shape.inc";fi
 shape "$virgl" struct virtio_gpu_virgl_resource >> "$out/qemu-shape.inc"
 shape "$virgl" struct virtio_gpu_virgl_hostmem_region >> "$out/qemu-shape.inc"
 sed -n '1,13p' "$qemu/hw/display/virtio-gpu.c" > "$out/mapping.inc"
 for name in virtio_gpu_create_mapping_iov virtio_gpu_cleanup_mapping_iov;do extract "$qemu/hw/display/virtio-gpu.c" "$name" >> "$out/mapping.inc";done
 : > "$out/base-cleanup.inc"
 for name in virtio_gpu_cleanup_mapping virtio_gpu_resource_destroy;do extract "$qemu/hw/display/virtio-gpu.c" "$name" >> "$out/base-cleanup.inc";done
 awk '/^#define VIRTIO_GPU_FILL_CMD\(out\)/{hits++;active=1}active{print;if(/while \(0\)/){active=0;done++}}END{if(hits!=1||active||done!=1)exit 1}' "$qemu/include/hw/virtio/virtio-gpu.h" > "$out/fill.inc"
 sed -n '1,13p' "$virgl" > "$out/qemu.inc"
 extract "$virgl" virtio_gpu_virgl_find_resource >> "$out/qemu.inc"
 if [ "$tree" != baseline ];then for name in detach_classic_backing release_classic_backing;do extract "$virgl" "$name" >> "$out/qemu.inc";done;fi
 for name in to_hostmem_region virtio_gpu_virgl_finish_unmap virtio_gpu_virgl_unmap_resource_blob virtio_gpu_virgl_destroy_hostmem_region virtio_gpu_virgl_resource_destroy virgl_create_resource_error virgl_cmd_create_resource_2d virgl_cmd_create_resource_3d virgl_cmd_resource_unref virgl_resource_attach_backing virgl_resource_detach_backing;do
  extract "$virgl" "$name" > "$out/$name.inc"
  if [ "$tree" = mutant ] && [ "$name" = virtio_gpu_virgl_finish_unmap ];then
   # Causal omission mutant: retain original full function except removing
   # the two new helper calls in this one production cleanup consumer.
   sed '/        detach_classic_backing(res);/d; /        release_classic_backing(g, res);/d' "$out/$name.inc" > "$out/mutant-finish.inc"
   cat "$out/mutant-finish.inc" >> "$out/qemu.inc"
  else cat "$out/$name.inc" >> "$out/qemu.inc";fi
 done
 printf '%s\n' '#if VIRGL_VERSION_MAJOR >= 1' >> "$out/qemu.inc"
 extract "$virgl" virgl_cmd_resource_create_blob >> "$out/qemu.inc"
 printf '%s\n' '#endif' >> "$out/qemu.inc"
 sed -n '1,23p' "$src/vrend/vrend_renderer.c" > "$out/pipe.inc"
 for name in vrend_pipe_resource_unref vrend_pipe_resource_attach_iov vrend_pipe_resource_detach_iov;do extract "$src/vrend/vrend_renderer.c" "$name" >> "$out/pipe.inc";done
 sed -n '1,23p' "$src/virgl_resource.c" > "$out/resource.inc"
 for name in virgl_resource_destroy_func virgl_resource_lookup virgl_resource_remove virgl_resource_attach_iov virgl_resource_detach_iov;do extract "$src/virgl_resource.c" "$name" >> "$out/resource.inc";done
 sed -n '1,23p' "$src/virglrenderer.c" > "$out/api.inc"
 for name in virgl_renderer_resource_attach_iov virgl_renderer_resource_detach_iov virgl_renderer_resource_unref;do extract "$src/virglrenderer.c" "$name" >> "$out/api.inc";done
 extract "$src/vrend/vrend_renderer.h" vrend_resource_reference > "$out/reference.inc"
 extract "$src/vrend/vrend_renderer.c" vrend_renderer_resource_destroy > "$out/renderer-destroy.inc"
 awk '/^#define VREND_STORAGE_/{print}' "$src/vrend/vrend_renderer.h" > "$out/storage.inc"
 : > "$out/pipe-reference.inc"
 for name in pipe_is_referenced pipe_reference_described pipe_reference;do extract "$src/gallium/auxiliary/util/u_inlines.h" "$name" >> "$out/pipe-reference.inc";done
 shape "$src/vrend/vrend_renderer.c" struct vrend_query > "$out/query-shape.inc"
 shape "$src/virgl_protocol.h" struct virgl_host_query_state >> "$out/query-shape.inc"
 : > "$out/query.inc"
 for name in vrend_create_query vrend_check_query vrend_destroy_query;do extract "$src/vrend/vrend_renderer.c" "$name" >> "$out/query.inc";done
 awk '{s=$0;while(match(s,/GL_[A-Z_0-9]+|feat_[a-z_0-9]+|PIPE_QUERY_[A-Z_0-9]+|VIRGL_ERROR_[A-Z_0-9]+|VIRGL_OBJECT_[A-Z_0-9]+/)){print substr(s,RSTART,RLENGTH);s=substr(s,RSTART+RLENGTH)}}' "$out/query.inc" | sort -u | awk '{print "#define " $0 " " ++n}' > "$out/query-defs.inc"
 for version in 0 1;do
  for mode in plain sanitized release;do
   [ "$mode" != release ] || [ "$tree" = patched ] || continue
   set -- -DVIRGL_VERSION_MAJOR="$version"
   if [ "$tree" != baseline ];then set -- "$@" -DBACKING_PATCHED;fi
   if [ "$mode" = sanitized ];then set -- "$@" -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer;fi
   if [ "$mode" = release ];then set -- "$@" -DNDEBUG;fi
   "${CC:-cc}" -std=c11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-variable -Wno-unused-parameter -Wno-sign-compare "$@" -I"$out" -I"$src" -I"$src/vrend" "$recipe/tests/backing.c" "$src/vrend/iov.c" -o "$out/v$version-$mode" > "$out/compile-v$version-$mode.log" 2>&1 || { cat "$out/compile-v$version-$mode.log" >&2;exit 1; }
   if "$out/v$version-$mode" > "$out/v$version-$mode.log" 2>&1;then status=0;else status=$?;fi
   printf '%s\n' "$status" > "$out/v$version-$mode.status"
   if [ "$tree" = patched ] || { [ "$tree" = mutant ] && [ "$version" = 0 ]; };then
    [ "$status" -eq 0 ]
   elif [ "$tree" = baseline ];then [ "$status" -eq 1 ]
   else [ "$status" -eq 134 ];fi
   if [ "$tree" = baseline ];then grep -Fq 'FAIL: successful attach ledger owns exact split P/N' "$out/v$version-$mode.log";fi
   if [ "$tree" = mutant ];then
    # Older version has no deferred consumer; its causal omission is absent.
    if [ "$version" = 1 ];then grep -Fq 'Assertion failed: (!pipe_resource->iov && pipe_resource->base.reference.count==0)' "$out/v$version-$mode.log";fi
   fi
   if grep -E 'ERROR: AddressSanitizer|runtime error:|LeakSanitizer' "$out/v$version-$mode.log";then exit 1;fi
   tail -1 "$out/v$version-$mode.log"
  done
 done
 done
