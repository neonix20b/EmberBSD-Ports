#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
set -eu
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$1 out=$2 variant=$3
sh "$recipe/tests/extract-completion.sh" "$work" "$out" patched
sh "$recipe/tests/extract-wait-renderer.sh" "$work" "$out/renderer" "$variant"
cp "$out/renderer/"*.inc "$out/renderer/"*.h "$out/"
if [ "$variant" != baseline ];then
 for n in virtio_gpu_fence_poll virtio_gpu_virgl_init;do
  awk -v name="$n" -f "$recipe/tests/extract-lifecycle.awk" "$work/qemu/wait/hw/display/virtio-gpu-virgl.c" > "$out/wait-$n.inc"
  ruby - "$out" "$n" <<'RUBY'
p,n=ARGV;s=File.read(p+'/functions.inc');old=File.read(p+'/'+n+'.inc');raise unless s.scan(old).length==1;s.sub!(old,File.read(p+'/wait-'+n+'.inc'));File.write(p+'/functions.inc',s)
RUBY
 done
 awk -v name=virtio_gpu_gl_device_realize -f "$recipe/tests/extract-lifecycle.awk" "$work/qemu/completion/hw/display/virtio-gpu-gl.c" > "$out/old-realize.inc"
 awk -v name=virtio_gpu_gl_device_realize -f "$recipe/tests/extract-lifecycle.awk" "$work/qemu/wait/hw/display/virtio-gpu-gl.c" > "$out/new-realize.inc"
 ruby - "$out" <<'RUBY'
p=ARGV[0];s=File.read(p+'/functions.inc');old=File.read(p+'/old-realize.inc');raise unless s.scan(old).length==1;s.sub!(old,File.read(p+'/new-realize.inc'));File.write(p+'/functions.inc',s)
RUBY
fi
ruby "$recipe/tests/wait-qemu-seams.rb" "$out"
cp "$recipe/tests/wait-qemu-cases.h" "$out/"
