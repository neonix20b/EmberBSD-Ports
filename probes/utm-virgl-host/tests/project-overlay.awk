# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted whole selected-file mbox projection.
# Whole selected file sections, preserving their original mbox headers.
function flush() { if (chosen) { print header > out; printf "%s", section >> out; close(out) } section=""; chosen=0 }
/^From [0-9a-f]+ Mon Sep 17/ { flush(); commit=$2; header=$0 "\n"; inheader=1; next }
inheader { header=header $0 "\n"; if ($0=="---") inheader=0; next }
/^diff --git / {
 flush(); old=$3; new=$4; sub(/^a\//,"",old); sub(/^b\//,"",new)
 selected=(old=="hw/display/virtio-gpu-gl.c" || old=="hw/display/virtio-gpu-virgl.c" || old=="hw/display/virtio-gpu.c" || old=="include/hw/virtio/virtio-gpu.h" || new=="hw/display/virtio-gpu-gl.c" || new=="hw/display/virtio-gpu-virgl.c" || new=="hw/display/virtio-gpu.c" || new=="include/hw/virtio/virtio-gpu.h")
 print commit,old,new,selected ? "selected" : "excluded" > manifest
 if (selected) { if (old != new) exit 2; count++; out=sprintf("%s/%02d.patch",dir,count); print count,commit,old > inventory; chosen=1 }
 section=$0 "\n"; next
}
/^-- $/ { flush(); next }
/^(rename |copy |similarity |new file mode|deleted file mode|old mode|new mode|Binary files|GIT binary patch)/ { if (chosen) bad=1 }
{ if (section!="") section=section $0 "\n" }
END { flush(); if (count != 8 || bad) exit 3 }
