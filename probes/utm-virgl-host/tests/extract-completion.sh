#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Extend accepted lifecycle extraction; actual production bodies stay unchanged.
set -eu
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$1 out=$2 variant=$3
sh "$recipe/tests/extract-lifecycle.sh" qemu "$work" "$out"
q=$work/qemu/lifecycle
[ "$variant" = baseline ] || q=$work/qemu/completion
f() { awk -v name="$2" -f "$recipe/tests/extract-lifecycle.awk" "$1"; }
# Replace the complete extracted dispatch using its exact accepted body.
f "$q/hw/display/virtio-gpu-virgl.c" virtio_gpu_virgl_dispatch_cmd > "$out/completion-dispatch.inc"
ruby - "$out" <<'RUBY'
p=ARGV[0];s=File.read(p+'/functions.inc');old=File.read(p+'/virtio_gpu_virgl_dispatch_cmd.inc');raise unless s.scan(old).length==1;s.sub!(old,File.read(p+'/completion-dispatch.inc'));File.write(p+'/functions.inc',s)
RUBY
for n in virgl_cmd_submit_3d virgl_cmd_transfer_to_host_2d virgl_cmd_transfer_to_host_3d virgl_cmd_transfer_from_host_3d;do
 f "$q/hw/display/virtio-gpu-virgl.c" "$n" > "$out/$n.inc"
 awk '/^\{/{print ";";exit} /\{/{sub(/\{.*/,";");print;exit}{print}' "$out/$n.inc" >> "$out/protos.inc"
 cat "$out/$n.inc" >> "$out/functions.inc"
done
if [ "$variant" != baseline ];then
 f "$q/hw/display/virtio-gpu-virgl.c" virgl_report_completion_error > "$out/completion-helper.inc"
 awk '/^\{/{print ";";exit}{print}' "$out/completion-helper.inc" >> "$out/protos.inc"
 cat "$out/completion-helper.inc" >> "$out/functions.inc"
fi
: > "$out/completion-api.inc"
for n in virgl_renderer_submit_cmd virgl_renderer_transfer_write_iov virgl_renderer_transfer_read_iov virgl_renderer_create_fence virgl_renderer_context_create_fence;do f "$work/renderer-lifecycle/src/virglrenderer.c" "$n" >> "$out/completion-api.inc";done
: > "$out/completion-response.inc"
for n in virtio_gpu_ctrl_response virtio_gpu_ctrl_response_nodata;do f "$q/hw/display/virtio-gpu.c" "$n" >> "$out/completion-response.inc";done
ruby "$recipe/tests/completion-seams.rb" "$recipe/tests/lifecycle.c" > "$out/completion.c"
cp "$recipe"/tests/completion-*.h "$out/"
find "$out" -type f ! -name '*sha256.txt' -exec shasum -a 256 {} \; > "$out/completion-extracted-sha256.txt"
