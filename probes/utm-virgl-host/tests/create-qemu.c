/* SPDX-License-Identifier: BSD-2-Clause
 * Origin: EmberBSD, AI-assisted actual QEMU function seam.
 * Protocol structs/queue/transport/GLib seams are modeled here. Functions in
 * qemu.inc, response.inc, queue.inc and fill.inc are extracted without edits.
 */
#include <assert.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/queue.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <unistd.h>
#include "virglrenderer.h"
#include "virgl_hw.h"
#define VIRGL_VERSION_MAJOR 1
#define QTAILQ_HEAD TAILQ_HEAD
#define QTAILQ_ENTRY TAILQ_ENTRY
#define QTAILQ_INIT TAILQ_INIT
#define QTAILQ_FIRST TAILQ_FIRST
#define QTAILQ_EMPTY TAILQ_EMPTY
#define QTAILQ_INSERT_HEAD TAILQ_INSERT_HEAD
#define QTAILQ_INSERT_TAIL TAILQ_INSERT_TAIL
#define QTAILQ_REMOVE TAILQ_REMOVE
#define QTAILQ_FOREACH_SAFE(v,h,f,t) for ((v)=TAILQ_FIRST(h); (v) && ((t)=TAILQ_NEXT(v,f),1); (v)=(t))
#define container_of(p,t,f) ((t *)((char *)(p)-offsetof(t,f)))
#define LOG_GUEST_ERROR 1
#define VIRTIO_GPU_FLAG_FENCE 1
#define VIRTIO_GPU_FLAG_INFO_RING_IDX 2
#define VIRTIO_GPU_RESOURCE_FLAG_Y_0_TOP 1
/* The numeric wire constants are the pinned QEMU protocol subset. */
enum virtio_gpu_ctrl_type {
 VIRTIO_GPU_CMD_GET_DISPLAY_INFO=0x100, VIRTIO_GPU_CMD_RESOURCE_CREATE_2D,
 VIRTIO_GPU_CMD_RESOURCE_UNREF, VIRTIO_GPU_CMD_SET_SCANOUT,
 VIRTIO_GPU_CMD_RESOURCE_FLUSH, VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D,
 VIRTIO_GPU_CMD_RESOURCE_ATTACH_BACKING, VIRTIO_GPU_CMD_RESOURCE_DETACH_BACKING,
 VIRTIO_GPU_CMD_GET_CAPSET_INFO, VIRTIO_GPU_CMD_GET_CAPSET, VIRTIO_GPU_CMD_GET_EDID,
 VIRTIO_GPU_CMD_RESOURCE_CREATE_BLOB, VIRTIO_GPU_CMD_SET_SCANOUT_BLOB,
 VIRTIO_GPU_CMD_CTX_CREATE=0x200, VIRTIO_GPU_CMD_CTX_DESTROY,
 VIRTIO_GPU_CMD_CTX_ATTACH_RESOURCE, VIRTIO_GPU_CMD_CTX_DETACH_RESOURCE,
 VIRTIO_GPU_CMD_RESOURCE_CREATE_3D, VIRTIO_GPU_CMD_TRANSFER_TO_HOST_3D,
 VIRTIO_GPU_CMD_TRANSFER_FROM_HOST_3D, VIRTIO_GPU_CMD_SUBMIT_3D,
 VIRTIO_GPU_CMD_RESOURCE_MAP_BLOB, VIRTIO_GPU_CMD_RESOURCE_UNMAP_BLOB,
 VIRTIO_GPU_RESP_OK_NODATA=0x1100,
 VIRTIO_GPU_RESP_ERR_UNSPEC=0x1200, VIRTIO_GPU_RESP_ERR_OUT_OF_MEMORY,
 VIRTIO_GPU_RESP_ERR_INVALID_SCANOUT_ID, VIRTIO_GPU_RESP_ERR_INVALID_RESOURCE_ID,
 VIRTIO_GPU_RESP_ERR_INVALID_CONTEXT_ID, VIRTIO_GPU_RESP_ERR_INVALID_PARAMETER
};
struct virtio_gpu_ctrl_hdr { uint32_t type,flags; uint64_t fence_id; uint32_t ctx_id; uint8_t ring_idx; uint8_t padding[3]; };
struct virtio_gpu_resource_create_2d { struct virtio_gpu_ctrl_hdr hdr; uint32_t resource_id,format,width,height; };
struct virtio_gpu_resource_create_3d { struct virtio_gpu_ctrl_hdr hdr; uint32_t resource_id,target,format,bind,width,height,depth,array_size,last_level,nr_samples,flags,padding; };
struct virtio_gpu_resource_unref { struct virtio_gpu_ctrl_hdr hdr; uint32_t resource_id,padding; };
typedef struct VirtIOGPU VirtIOGPU;
struct virtio_gpu_simple_resource { uint32_t resource_id,width,height,format; int dmabuf_fd; struct iovec *iov; int iov_cnt; QTAILQ_ENTRY(virtio_gpu_simple_resource) next; };
struct virtio_gpu_virgl_resource { struct virtio_gpu_simple_resource base; void *mr; };
struct virtio_gpu_ctrl_command {
 struct { struct iovec *out_sg,*in_sg; unsigned out_num,in_num; } elem;
 void *vq; struct virtio_gpu_ctrl_hdr cmd_hdr; uint32_t error;
 bool finished,suspended,deferred; QTAILQ_ENTRY(virtio_gpu_ctrl_command) next;
};
struct VirtIOGPU {
 QTAILQ_HEAD(,virtio_gpu_simple_resource) reslist;
 QTAILQ_HEAD(,virtio_gpu_ctrl_command) cmdq,fenceq;
 struct { int renderer_blocked,conf; } parent_obj;
 struct { unsigned requests,max_inflight; } stats;
 unsigned inflight; bool processing_cmdq;
};
typedef struct { void (*process_cmd)(VirtIOGPU *,struct virtio_gpu_ctrl_command *); } VirtIOGPUClass;
static VirtIOGPUClass gpu_class;
#define VIRTIO_GPU_GET_CLASS(g) (&gpu_class)
#define VIRTIO_DEVICE(g) (g)
#define virtio_gpu_stats_enabled(conf) ((conf)!=0)
#define trace_virtio_gpu_cmd_res_create_2d(...) ((void)0)
#define trace_virtio_gpu_cmd_res_create_3d(...) ((void)0)
#define trace_virtio_gpu_cmd_res_unref(...) ((void)0)
#define trace_virtio_gpu_fence_ctrl(...) ((void)0)
#define trace_virtio_gpu_fence_resp(...) ((void)0)
#define trace_virtio_gpu_cmd_suspended(...) ((void)0)
#define trace_virtio_gpu_inc_inflight_fences(...) ((void)0)
#define trace_virtio_gpu_dec_inflight_fences(...) ((void)0)
#define qemu_log_mask(...) ((void)0)
#define virtio_gpu_ctrl_hdr_bswap(h) ((void)(h))
static unsigned q_calls,q_published,q_allocated,q_freed,q_unrefs,responses,fence_calls;
static int renderer_return;
static bool wrapper_oom;
static void *wrapper_ptrs[128];
static struct virgl_renderer_resource_create_args forwarded;
static VirtIOGPU *active_gpu;
static struct virtio_gpu_ctrl_hdr response;
static int failures,cases;
static void check(bool ok,const char *name) { cases++; if(!ok) { failures++; printf("FAIL: %s\n",name); } }
#ifdef CREATE_GLIB_ALLOCATOR
/* Optional existing GLib seam. Overflow injection reaches its real fatal or
 * recoverable allocator without asking the host to allocate a huge region. */
extern void *g_malloc0_n(size_t,size_t);
extern void *g_try_malloc0_n(size_t,size_t);
extern void g_free(void *);
#endif
static void *q_allocate(size_t size,bool fatal) {
#ifdef CREATE_GLIB_ALLOCATOR
 if(wrapper_oom) return fatal?g_malloc0_n(SIZE_MAX,2):g_try_malloc0_n(SIZE_MAX,2);
 void *p=fatal?g_malloc0_n(1,size):g_try_malloc0_n(1,size);
#else
 if(wrapper_oom) { if(fatal) abort(); return NULL; }
 void *p=calloc(1,size);
#endif
 assert(p); assert(q_allocated<128);
 wrapper_ptrs[q_allocated++]=p; return p;
}
#define g_new0(t,n) ((t *)q_allocate(sizeof(t)*(n),true))
#define g_try_new0(t,n) ((t *)q_allocate(sizeof(t)*(n),false))
static void q_free(void *p) {
 for(unsigned i=0;i<q_allocated;i++) if(wrapper_ptrs[i]==p) { wrapper_ptrs[i]=NULL; q_freed++; break; }
#ifdef CREATE_GLIB_ALLOCATOR
 g_free(p);
#else
 free(p);
#endif
}
#define g_free q_free
static size_t iov_to_buf(const struct iovec *v,unsigned n,size_t off,void *buf,size_t len) {
 assert(n==1 && off==0); size_t s=v->iov_len<len?v->iov_len:len; memcpy(buf,v->iov_base,s); return s;
}
static size_t iov_from_buf(struct iovec *v,unsigned n,size_t off,const void *buf,size_t len) {
 assert(n==1 && off==0 && v->iov_len>=len); memcpy(v->iov_base,buf,len); memcpy(&response,buf,sizeof(response)); return len;
}
static void virtqueue_push(void *vq,void *elem,size_t s) { (void)vq;(void)elem;assert(s==sizeof(response)); responses++; }
static void virtio_notify(VirtIOGPU *g,void *vq) { (void)g;(void)vq; }
static struct virtio_gpu_simple_resource *virtio_gpu_find_resource(VirtIOGPU *g,uint32_t id) {
 struct virtio_gpu_simple_resource *r; TAILQ_FOREACH(r,&g->reslist,next) if(r->resource_id==id) return r; return NULL;
}
static int virtio_gpu_virgl_unmap_resource_blob(VirtIOGPU *g,struct virtio_gpu_virgl_resource *r,bool *s) { (void)g;assert(!r->mr); *s=false; return 0; }
static void virtio_gpu_cleanup_mapping_iov(VirtIOGPU *g,struct iovec *v,int n) { (void)g;(void)v;(void)n; abort(); }
#ifndef CREATE_INTEGRATED
int virgl_renderer_resource_create(struct virgl_renderer_resource_create_args *a,struct iovec *v,uint32_t n) {
 assert(v==NULL && n==0); q_calls++; forwarded=*a;
 if(virtio_gpu_find_resource(active_gpu,a->handle)) q_published++;
 return renderer_return;
}
void virgl_renderer_resource_unref(uint32_t id) { (void)id; q_unrefs++; }
#else
/* Real renderer API is above this seam. Count at its external trace boundary. */
#endif
void virgl_renderer_resource_detach_iov(int id,struct iovec **v,int *n) { (void)id; *v=NULL; *n=0; }
void virgl_renderer_force_ctx_0(void) {}
int virgl_renderer_create_fence(int id,uint32_t type) { (void)id;(void)type; fence_calls++; return 0; }
int virgl_renderer_context_create_fence(uint32_t id,uint32_t flags,uint32_t ring,uint64_t fence) { (void)id;(void)flags;(void)ring;(void)fence; fence_calls++;return 0; }
#define STUB(name) static void name(VirtIOGPU *g,struct virtio_gpu_ctrl_command *c) { (void)g;(void)c;abort(); }
STUB(virgl_cmd_context_create) STUB(virgl_cmd_context_destroy) STUB(virgl_cmd_submit_3d)
STUB(virgl_cmd_transfer_to_host_2d) STUB(virgl_cmd_transfer_to_host_3d) STUB(virgl_cmd_transfer_from_host_3d)
STUB(virgl_resource_attach_backing) STUB(virgl_resource_detach_backing) STUB(virgl_cmd_set_scanout)
STUB(virgl_cmd_resource_flush) STUB(virgl_cmd_ctx_attach_resource) STUB(virgl_cmd_ctx_detach_resource)
STUB(virgl_cmd_get_capset_info) STUB(virgl_cmd_get_capset) STUB(virtio_gpu_get_display_info)
STUB(virtio_gpu_get_edid) STUB(virgl_cmd_resource_create_blob) STUB(virgl_cmd_resource_map_blob) STUB(virgl_cmd_set_scanout_blob)
static void virgl_cmd_resource_unmap_blob(VirtIOGPU *g,struct virtio_gpu_ctrl_command *c,bool *s) { (void)g;(void)c;(void)s;abort(); }
#include "fill.inc"
#include "response.inc"
#include "qemu.inc"
#include "queue.inc"
static void init_gpu(VirtIOGPU *g) {
 memset(g,0,sizeof(*g)); QTAILQ_INIT(&g->reslist);QTAILQ_INIT(&g->cmdq);QTAILQ_INIT(&g->fenceq);
 gpu_class.process_cmd=virtio_gpu_virgl_process_cmd;active_gpu=g;
 q_calls=q_published=q_allocated=q_freed=q_unrefs=responses=fence_calls=0;
 renderer_return=0;wrapper_oom=false;memset(wrapper_ptrs,0,sizeof(wrapper_ptrs));memset(&response,0,sizeof(response));
}
static struct virtio_gpu_resource_create_3d body3(uint32_t id) {
 struct virtio_gpu_resource_create_3d b={0}; b.hdr.type=VIRTIO_GPU_CMD_RESOURCE_CREATE_3D;
 b.hdr.flags=VIRTIO_GPU_FLAG_FENCE; b.hdr.fence_id=77; b.hdr.ctx_id=9;
 b.resource_id=id;b.target=2;b.format=1;b.bind=2;b.width=31;b.height=17;b.depth=1;b.array_size=1;return b;
}
static void send_body(VirtIOGPU *g,void *body,size_t len) {
 unsigned replies_before=responses, fences_before=fence_calls;
 struct iovec out={body,len},in={&response,sizeof(response)};
 struct virtio_gpu_ctrl_command *cmd=calloc(1,sizeof(*cmd)); assert(cmd);
 cmd->elem.out_sg=&out;cmd->elem.out_num=1;cmd->elem.in_sg=&in;cmd->elem.in_num=1;
 QTAILQ_INSERT_TAIL(&g->cmdq,cmd,next);virtio_gpu_process_cmdq(g);
 /* Real fence callbacks are invoked while these modeled SGs remain alive. */
 if(g->inflight) {
  check(responses==replies_before && fence_calls==fences_before+1,"success waits for fence callback");
  if(((struct virtio_gpu_ctrl_hdr *)body)->flags & VIRTIO_GPU_FLAG_INFO_RING_IDX) {
   virgl_write_fence(g,UINT32_MAX);check(responses==replies_before,"global callback excludes context ring");
   virgl_write_context_fence(g,8,3,UINT64_MAX);check(responses==replies_before,"wrong context callback excluded");
   virgl_write_context_fence(g,9,3,77);
  } else { virgl_write_context_fence(g,9,3,77);check(responses==replies_before,"context callback excludes global");virgl_write_fence(g,77); }
  check(g->inflight==0 && QTAILQ_EMPTY(&g->fenceq),"fence ownership retired exactly once");
 }
}
static void send_create(VirtIOGPU *g,int dim,uint32_t id,size_t trim,bool ring) {
 if(dim==2) {
  struct virtio_gpu_resource_create_2d b={0};b.hdr.type=VIRTIO_GPU_CMD_RESOURCE_CREATE_2D;
  b.hdr.flags=VIRTIO_GPU_FLAG_FENCE;b.hdr.fence_id=77;b.hdr.ctx_id=9;
  if(ring) { b.hdr.flags|=VIRTIO_GPU_FLAG_INFO_RING_IDX;b.hdr.ring_idx=3; }
  b.resource_id=id;b.format=1;b.width=31;b.height=17;send_body(g,&b,sizeof(b)-trim);
 } else { struct virtio_gpu_resource_create_3d b=body3(id); if(ring) { b.hdr.flags|=2;b.hdr.ring_idx=3; }send_body(g,&b,sizeof(b)-trim); }
}
static void dispose(VirtIOGPU *g) {
 while(!QTAILQ_EMPTY(&g->reslist)) { struct virtio_gpu_simple_resource *r=QTAILQ_FIRST(&g->reslist);QTAILQ_REMOVE(&g->reslist,r,next);q_free(r); }
}
#ifndef CREATE_INTEGRATED
static void reject_cases(int dim) {
 int errors[]={EINVAL,-EINVAL,ENOMEM,-ENOMEM,INT_MIN,INT_MAX};
 for(unsigned i=0;i<sizeof(errors)/sizeof(errors[0]);i++) {
  VirtIOGPU g;init_gpu(&g);renderer_return=errors[i];send_create(&g,dim,11,0,false);
  uint32_t wanted=(errors[i]==ENOMEM||errors[i]==-ENOMEM)?VIRTIO_GPU_RESP_ERR_OUT_OF_MEMORY:VIRTIO_GPU_RESP_ERR_UNSPEC;
  check(response.type==wanted && responses==1,"renderer failure reaches one error response");
  check(response.fence_id==77 && response.ctx_id==9 && response.flags==1,"error preserves original fence header");
  check(QTAILQ_EMPTY(&g.reslist) && q_allocated==1 && q_freed==1,"failed CREATE unpublished wrapper freed once");
  check(q_published==0 && q_unrefs==0 && fence_calls==0,"no early publication, compensating unref or error fence");
  dispose(&g);
 }
 VirtIOGPU g;init_gpu(&g);send_create(&g,dim,11,1,false);
 check(response.type==VIRTIO_GPU_RESP_ERR_INVALID_PARAMETER && responses==1,"short complete-header CREATE rejected");
 check(q_calls==0 && q_allocated==0 && fence_calls==0,"short CREATE has no side effects");dispose(&g);
 init_gpu(&g);send_create(&g,dim,0,0,false);check(response.type==VIRTIO_GPU_RESP_ERR_INVALID_RESOURCE_ID && q_calls==0 && q_allocated==0,"zero ID rejected locally");
 for(int ring=0;ring<2;ring++) {
  init_gpu(&g);send_create(&g,dim,11,0,ring);struct virtio_gpu_simple_resource *r=QTAILQ_FIRST(&g.reslist);
  check(response.type==VIRTIO_GPU_RESP_OK_NODATA && responses==1 && q_calls==1 && q_published==0,"success publishes only after renderer once");
  check(r && r->resource_id==11 && r->width==31 && r->height==17 && r->format==1 && r->dmabuf_fd==-1 && !r->iov && !r->iov_cnt,"wrapper initialized and zeroed");
  struct virgl_renderer_resource_create_args expected={.handle=11,.target=2,.format=1,.bind=2,.width=31,.height=17,.depth=1,.array_size=1,.flags=dim==2?1:0};
  check(!memcmp(&forwarded,&expected,sizeof(expected)),"CREATE argument initialization forwarded exactly");
  send_create(&g,dim,11,0,ring);check(response.type==VIRTIO_GPU_RESP_ERR_INVALID_RESOURCE_ID && q_calls==1 && q_allocated==1 && q_unrefs==0,"duplicate ID preserves existing resource");
  struct virtio_gpu_resource_unref u={0};u.hdr.type=VIRTIO_GPU_CMD_RESOURCE_UNREF;u.resource_id=11;send_body(&g,&u,sizeof(u));
  check(QTAILQ_EMPTY(&g.reslist) && q_unrefs==1 && q_freed==1,"normal UNREF owns successful resource exactly once");
 }
 init_gpu(&g);renderer_return=EINVAL;send_create(&g,dim,11,0,false);renderer_return=0;send_create(&g,dim,11,0,false);
 check(response.type==VIRTIO_GPU_RESP_OK_NODATA && q_calls==2 && q_freed==1 && q_allocated==2,"failed ID reusable without ghost publication");dispose(&g);
 /* 3D handler forwarding accepts unchanged format/geometry metadata. The seam
  * deliberately does not prove GL acceptance or host allocation size bounds. */
 if(dim==3) {
  uint32_t formats[]={VIRGL_FORMAT_B8G8R8A8_UNORM,VIRGL_FORMAT_DXT1_RGBA,VIRGL_FORMAT_Z24X8_UNORM,VIRGL_FORMAT_R8_UNORM};
  for(unsigned i=0;i<4;i++) { init_gpu(&g);struct virtio_gpu_resource_create_3d b=body3(11);b.format=formats[i];b.target=i==3?0:2;b.width=i==3?1:31;b.height=1;b.depth=1;b.nr_samples=i==2?4:0;b.flags=0;b.bind=i==3?0x80000:2;
   send_body(&g,&b,sizeof(b));check(forwarded.format==b.format && forwarded.nr_samples==b.nr_samples && forwarded.bind==b.bind && forwarded.width==b.width,"unchanged compressed/depth/MSAA/staging forwarding");dispose(&g);
  }
  init_gpu(&g);struct virtio_gpu_resource_create_3d b=body3(11);b.target=8;b.bind=0x102;b.depth=7;b.array_size=6;b.last_level=4;b.nr_samples=8;b.flags=3;
  send_body(&g,&b,sizeof(b));check(forwarded.target==8 && forwarded.depth==7 && forwarded.array_size==6 && forwarded.last_level==4 && forwarded.nr_samples==8 && forwarded.flags==3,"all variable 3D fields forwarded");dispose(&g);
 }
 fflush(NULL);pid_t pid=fork();assert(pid>=0);if(pid==0) { init_gpu(&g);wrapper_oom=true;send_create(&g,dim,11,0,false);_exit(response.type==VIRTIO_GPU_RESP_ERR_OUT_OF_MEMORY && responses==1 && q_calls==0 && q_allocated==0 && fence_calls==0?0:1); }
 int st;assert(waitpid(pid,&st,0)==pid);check(WIFEXITED(st)&&WEXITSTATUS(st)==0,"wrapper OOM normally completes without renderer or abort");
}
int main(void) { reject_cases(2);reject_cases(3);printf("QEMU: %d assertions, %d failed\n",cases,failures);return failures?1:0; }
#endif
