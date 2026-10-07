# SPDX-License-Identifier: BSD-2-Clause
# Extend only accepted external C8c3 seams; do not substitute production bodies.
require 'digest'
p=ARGV[0];s=File.read(p+'/completion.c')
def once(s,a,b)
 raise "Nonunique wait seam anchor: #{a[0,70]}" unless s.scan(a).length==1
 s.sub!(a,b)
end
once(s,"#include \"virglrenderer.h\"\n#ifdef LIFECYCLE_NO_ABI","#define WAIT_QEMU 1\n#include \"virglrenderer.h\"\n#ifdef WAIT_NO_ABI\n#undef VIRGL_RENDERER_EMBER_CLASSIC_WAIT_ABI\n#endif\n#ifdef LIFECYCLE_NO_ABI")
a=s.index('void virgl_renderer_cleanup(void *p){');b=s.index('static void virtio_gpu_virgl_resource_destroy',a);raise unless a&&b;s[a...b]=''
a=s.index('int virgl_renderer_init(void *p,int flags,struct virgl_renderer_callbacks *c)');b=s.index('static VirtIOGPU *active_g;',a);raise unless a&&b;s[a...b]=''
a=s.index('void virgl_renderer_poll(void){');b=s.index('void virgl_renderer_force_ctx_0',a);raise unless a&&b;s[a...b]=''
once(s,'#include "completion-api.inc"',"#include \"completion-api.inc\"\n#include \"wait-renderer-seams.h\"")
once(s,'#include "completion-cases.h"','#include "wait-qemu-cases.h"')
File.write(p+'/wait-qemu.c',s)
pth=p+'/completion-api.h';s=File.read(pth)
raise 'Accepted completion API seam drift' unless Digest::SHA256.hexdigest(s)=='25b598bf8f75144b75b0dc33da506de84f004f1e32bd980686fecd825a8d5906'
once(s,'static struct {bool vrend_initialized;struct virgl_renderer_callbacks *cbs;} state={true,&virtio_gpu_3d_cbs};',"#include \"wait-api-state.inc\"\nstatic struct global_state state;")
File.write(pth,s)
