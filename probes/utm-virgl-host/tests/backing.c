/* SPDX-License-Identifier: BSD-2-Clause
 * Origin: EmberBSD, AI-assisted actual-function ownership regression seam.
 * Framework, DMA mapping, hash table and GL are external seams. Extracted
 * functions are unmodified; pipe/QEMU structs are reduced field seams, not ABI.
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
#include <sys/mman.h>
#include <sys/queue.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <unistd.h>
#ifdef NDEBUG
/* Keep seam observers live while production helpers compile with NDEBUG.
 * The production fail-stop is explicit abort(), independent of assert. */
#undef assert
#define assert(e) ((e)?(void)0:(fprintf(stderr,"test seam invariant: %s\n",#e),abort()))
#endif
#define UNUSED __attribute__((unused))
#define TRACE_FUNC() ((void)0)
#define has_bit(bits,mask) (((bits)&(mask))!=0)
#define BIT(n) (1u<<(n))
#include "storage.inc"
#define QTAILQ_HEAD TAILQ_HEAD
#define QTAILQ_ENTRY TAILQ_ENTRY
#define QTAILQ_INSERT_HEAD TAILQ_INSERT_HEAD
#define QTAILQ_INSERT_TAIL TAILQ_INSERT_TAIL
#define QTAILQ_REMOVE TAILQ_REMOVE
#define container_of(p,t,f) ((t *)((char *)(p)-offsetof(t,f)))
#define LOG_GUEST_ERROR 1
#define qemu_log_mask(...) ((void)0)
#define trace_virtio_gpu_cmd_res_back_attach(...) ((void)0)
#define trace_virtio_gpu_cmd_res_back_detach(...) ((void)0)
#define trace_virtio_gpu_cmd_res_unref(...) ((void)0)
#define trace_virtio_gpu_cmd_res_create_2d(...) ((void)0)
#define trace_virtio_gpu_cmd_res_create_3d(...) ((void)0)
#define trace_virtio_gpu_cmd_res_create_blob(...) ((void)0)
#define virtio_gpu_create_blob_bswap(b) ((void)(b))
#define virtio_gpu_blob_enabled(c) true
#define VIRTIO_GPU_BLOB_MEM_HOST3D 2
#define DMA_DIRECTION_TO_DEVICE 1
#define MEMTXATTRS_UNSPECIFIED 0
#define le64_to_cpu(a) (a)
#define le32_to_cpu(a) (a)
#define VIRTIO_GPU_RESP_ERR_UNSPEC 0x1200
#define VIRTIO_GPU_RESP_ERR_OUT_OF_MEMORY 0x1201
#define VIRTIO_GPU_RESP_ERR_INVALID_RESOURCE_ID 0x1203
#define VIRTIO_GPU_RESP_ERR_INVALID_PARAMETER 0x1205
#define VIRTIO_GPU_RESP_OK_NODATA 0x1100
#define VIRTIO_GPU_RESOURCE_FLAG_Y_0_TOP 1
#define VIRTIO_DEVICE(g) (g)
#define VIRTIO_GPU_BASE(g) (&(g)->parent_obj)
#define VIRTIO_GPU_GL(g) (&(g)->gl)
typedef uint64_t hwaddr;
typedef struct { void (*free)(void *); } Object;
typedef struct { bool enabled; } MemoryRegion;
#define OBJECT(v) (&(v)->parent_obj)
typedef void Error;
typedef struct VirtIOGPU VirtIOGPU;
struct virtio_gpu_ctrl_hdr { uint32_t type,flags; uint64_t fence_id; uint32_t ctx_id; uint8_t ring_idx,padding[3]; };
struct virtio_gpu_resource_attach_backing { struct virtio_gpu_ctrl_hdr hdr; uint32_t resource_id,nr_entries; };
struct virtio_gpu_resource_detach_backing { struct virtio_gpu_ctrl_hdr hdr; uint32_t resource_id,padding; };
struct virtio_gpu_resource_unref { struct virtio_gpu_ctrl_hdr hdr; uint32_t resource_id,padding; };
struct virtio_gpu_resource_create_2d { struct virtio_gpu_ctrl_hdr hdr; uint32_t resource_id,format,width,height; };
struct virtio_gpu_resource_create_3d { struct virtio_gpu_ctrl_hdr hdr; uint32_t resource_id,target,format,bind,width,height,depth,array_size,last_level,nr_samples,flags,padding; };
struct virtio_gpu_resource_create_blob {struct virtio_gpu_ctrl_hdr hdr;uint32_t resource_id,blob_mem,blob_flags,nr_entries;uint64_t blob_id,size;};
struct virgl_renderer_resource_create_blob_args {uint32_t res_handle,ctx_id,blob_mem,blob_flags;uint64_t blob_id,size;struct iovec *iovecs;uint32_t num_iovs;};
struct virgl_renderer_resource_info {int fd;};
struct virgl_renderer_resource_create_args { uint32_t handle,target,format,bind,width,height,depth,array_size,last_level,nr_samples,flags; };
struct virtio_gpu_mem_entry { uint64_t addr; uint32_t length,padding; };
struct virtio_gpu_ctrl_command { struct {struct iovec *out_sg; unsigned out_num;} elem; uint32_t error; bool deferred; };
struct virtio_gpu_simple_resource { uint32_t resource_id,width,height,format; int dmabuf_fd; struct iovec *iov; uint32_t iov_cnt; uint64_t *addrs; bool blob; unsigned scanout_bitmask; void *image; uint64_t hostmem,blob_size; QTAILQ_ENTRY(virtio_gpu_simple_resource) next; };
#include "qemu-shape.inc"
typedef struct { int renderer_blocked; MemoryRegion hostmem; struct {int max_outputs;} conf; } VirtIOGPUBase;
typedef struct { QTAILQ_HEAD(,virtio_gpu_virgl_hostmem_region) unmap_done_list; } VirtIOGPUGL;
struct VirtIOGPU { void *dma_as; QTAILQ_HEAD(,virtio_gpu_simple_resource) reslist; VirtIOGPUBase parent_obj; VirtIOGPUGL gl; uint64_t hostmem; };
static int failures,checks;
static unsigned maps,unmaps,arrays_freed,renderer_unrefs,responses,renderer_detaches,host_unmaps,wrapper_frees,pipe_destroyed,list_removed;
static unsigned stale_ledger,attach_calls;
static int map_failure=-1,detach_injection;
static uint32_t metadata_count;
static bool metadata_cleanup,create_failure;
static bool invariant_child;
static void check(bool ok,const char *name) { checks++; if(!ok){failures++;printf("FAIL: %s\n",name);} }
struct allocation {void *p;bool live;};
static struct allocation allocs[1024]; static unsigned alloc_count;
static void *tracked_array;
static struct virtio_gpu_virgl_resource *tracked_wrapper;
static void *q_alloc(size_t n) { void *p=malloc(n?n:1);assert(p);allocs[alloc_count++]=(struct allocation){p,true};assert(alloc_count<1024);return p; }
static void *q_zero(size_t n) {void *p=q_alloc(n);memset(p,0,n);return p;}
static void *q_renew(void *p,size_t n) { if(!p)return q_alloc(n);for(unsigned i=0;i<alloc_count;i++)if(allocs[i].p==p && allocs[i].live){void *r=realloc(p,n);assert(r);allocs[i].p=r;return r;}abort(); }
static void q_free(void *p) {
 if(!p)return;
 if(p==tracked_array){if(invariant_child)_exit(90);arrays_freed++;tracked_array=NULL;}
 if(p==tracked_wrapper){
#ifdef BACKING_PATCHED
  if(tracked_wrapper->classic_backing_state!=CLASSIC_BACKING_NONE)stale_ledger++;
#endif
  wrapper_frees++;tracked_wrapper=NULL;
 }
 for(unsigned i=0;i<alloc_count;i++)if(allocs[i].p==p && allocs[i].live){allocs[i].live=false;free(p);return;}
 abort();
}
#define g_malloc q_alloc
#define g_free q_free
#define g_renew(t,p,n) ((t *)q_renew(p,sizeof(t)*(n)))
#define g_new0(t,n) ((t *)q_zero(sizeof(t)*(n)))
#define g_try_new0 g_new0
static void q_autofree(void *slot) {q_free(*(void **)slot);}
#define g_autofree __attribute__((cleanup(q_autofree)))
static void *g_steal_pointer(void *slot) {void *p=*(void **)slot;*(void **)slot=NULL;return p;}
struct dma_page {void *p;bool live;size_t len;}; static struct dma_page pages[512]; static unsigned npages;
static void *dma_memory_map(UNUSED void *as,UNUSED uint64_t a,hwaddr *len,UNUSED int d,UNUSED int attrs) {
 if(map_failure>=0 && maps==(unsigned)map_failure)return NULL;
 if(*len>8)*len=8;assert(*len);
 void *p=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);assert(p!=MAP_FAILED);
 pages[npages++]=(struct dma_page){p,true,*len};maps++;return p;
}
static void dma_memory_unmap(UNUSED void *as,void *p,size_t len,UNUSED int d,size_t done) {
 assert(len==done);if(invariant_child)_exit(90);
 for(unsigned i=0;i<npages;i++)if(pages[i].p==p && pages[i].live){assert(pages[i].len==len);pages[i].live=false;unmaps++;assert(mprotect(p,4096,PROT_NONE)==0);return;}
 abort();
}
static size_t iov_to_buf(const struct iovec *v,unsigned n,size_t offset,void *p,size_t len) {
 assert(n==1);if(offset>=v->iov_len)return 0;size_t size=v->iov_len-offset;if(size>len)size=len;memcpy(p,(char *)v->iov_base+offset,size);return size;
}
static struct virtio_gpu_simple_resource *virtio_gpu_find_resource(VirtIOGPU *g,uint32_t id) {struct virtio_gpu_simple_resource *r;TAILQ_FOREACH(r,&g->reslist,next)if(r->resource_id==id)return r;return NULL;}
static void virtio_gpu_fini_udmabuf(UNUSED void *r) {abort();}
static void virtio_gpu_disable_scanout(UNUSED VirtIOGPU *g,UNUSED int i) {abort();}
static void qemu_pixman_image_unref(void *p) {assert(!p);}
static void virtio_gpu_ctrl_response_nodata(UNUSED VirtIOGPU *g,UNUSED struct virtio_gpu_ctrl_command *c,uint32_t value) {assert(value==VIRTIO_GPU_RESP_OK_NODATA);if(invariant_child)_exit(90);responses++;}
static void memory_region_set_enabled(MemoryRegion *mr,bool enabled) {mr->enabled=enabled;}
static void memory_region_del_subregion(UNUSED MemoryRegion *base,MemoryRegion *mr) {assert(!mr->enabled);}
static void object_unparent(UNUSED Object *object) { /* asynchronous grace period external seam */ }
static void error_report(const char *s) { fprintf(stderr,"%s\n",s);if(invariant_child){if(unmaps || renderer_unrefs || responses || arrays_freed)_exit(91);fprintf(stderr,"REFUSED: no DMA cleanup, unref or response\n");} }
void virtio_gpu_cleanup_mapping_iov(VirtIOGPU *,struct iovec *,uint32_t);
void actual_cleanup_mapping_iov(VirtIOGPU *,struct iovec *,uint32_t);

#define virtio_gpu_create_mapping_iov actual_create_mapping_iov
#define virtio_gpu_cleanup_mapping_iov actual_cleanup_mapping_iov
#include "mapping.inc"
#undef virtio_gpu_create_mapping_iov
#undef virtio_gpu_cleanup_mapping_iov
static int virtio_gpu_create_mapping_iov(VirtIOGPU *g,uint32_t n,uint32_t off,struct virtio_gpu_ctrl_command *c,uint64_t **a,struct iovec **v,uint32_t *nv) {
 if(metadata_count){*v=NULL;*nv=metadata_count;return 0;} /* count representation only; no huge storage */
 return actual_create_mapping_iov(g,n,off,c,a,v,nv);
}
void virtio_gpu_cleanup_mapping_iov(VirtIOGPU *g,struct iovec *v,uint32_t n) {
 if(metadata_count){assert(v==NULL && n==metadata_count);metadata_cleanup=true;return;}
 actual_cleanup_mapping_iov(g,v,n);
}
#include "base-cleanup.inc"
/* Renderer reduced resource/GL seam with real CUSTOM copy and ref consumers. */
typedef unsigned GLuint;
struct pipe_reference {int count;};
struct pipe_resource {struct pipe_reference reference;uint32_t width0;};
struct vrend_resource {struct pipe_resource base; const struct iovec *iov;int num_iovs;unsigned storage_bits;char *ptr;unsigned gl_id,tbo_tex_id,rbo_id,memobj;};
#include "virgl_resource.h"
struct list_head {struct list_head *next,*prev;};

#include "query-shape.inc"
struct vrend_sub_context {int sub_ctx_id;unsigned fake_occlusion_query_samples_passed_multiplier;};
struct vrend_context {struct vrend_sub_context *sub;};
static struct {bool finishing;} vrend_state;
static struct virgl_resource *global_resource;
static struct vrend_resource *pipe_resource;
static struct vrend_query *saved_query;
typedef const char *(*debug_reference_descriptor)(void *);
#define p_atomic_inc(p) (++*(p))
#define p_atomic_read(p) (*(p))
#define p_atomic_dec_zero(p) (--*(p)==0)
#define debug_reference(...) ((void)0)
static const char *debug_describe_reference(UNUSED void *p) {return "resource";}
#include "pipe-reference.inc"
static void renderer_free(void *p) {if(p==pipe_resource){assert(!pipe_resource->iov && pipe_resource->base.reference.count==0);pipe_destroyed++;pipe_resource=NULL;}free(p);}
static void glDeleteTextures(UNUSED int n,UNUSED unsigned *id) {abort();}
static void glDeleteBuffers(UNUSED int n,UNUSED unsigned *id) {abort();}
static void glDeleteRenderbuffers(UNUSED int n,UNUSED unsigned *id) {abort();}
static void glDeleteMemoryObjectsEXT(UNUSED int n,UNUSED unsigned *id) {abort();}
#define free renderer_free
#include "renderer-destroy.inc"
#undef free
#include "reference.inc"
#include "vrend_iov.h"
#include "pipe.inc"
static struct {void (*attach_iov)(struct pipe_resource *,const struct iovec *,int,void *);void (*detach_iov)(struct pipe_resource *,void *);void (*unref)(struct pipe_resource *,void *);void *data;} pipe_callbacks;
static void *virgl_resource_table;
#define uintptr_to_pointer(v) ((void *)(uintptr_t)(v))
static void *util_hash_table_get(UNUSED void *table,void *key) {return global_resource && global_resource->res_id==(uintptr_t)key?global_resource:NULL;}
static void util_hash_table_remove(void *,void *);
#include "resource.inc"
static void util_hash_table_remove(UNUSED void *table,void *key) {if(invariant_child)_exit(90);assert(global_resource && global_resource->res_id==(uintptr_t)key);virgl_resource_destroy_func(global_resource);global_resource=NULL;renderer_unrefs++;}
struct virgl_context_foreach_args {bool (*callback)(void *,void *);void *data;};
static bool detach_resource(UNUSED void *ctx,UNUSED void *res) {return true;}
static void virgl_context_foreach(UNUSED struct virgl_context_foreach_args *a) { /* no context-attached resource in this contract */ }
#define virgl_renderer_resource_detach_iov actual_renderer_detach_iov
#include "api.inc"
#undef virgl_renderer_resource_detach_iov
static void no_pipe_detach(UNUSED struct pipe_resource *r,UNUSED void *d) {}
void virgl_renderer_resource_detach_iov(int id,struct iovec **v,int *n) {
 renderer_detaches++;
 if(detach_injection==6)return; /* no-op API boundary injection */
 actual_renderer_detach_iov(id,v,n);
 if(detach_injection==1)*v=NULL;
 if(detach_injection==2)*v=(void *)(uintptr_t)1;
 if(detach_injection==3)*n=1;
 if(detach_injection==4)*n=-1;
}
static int virgl_renderer_resource_unmap(UNUSED uint32_t id) {host_unmaps++;return 0;}
static int virgl_renderer_resource_create(struct virgl_renderer_resource_create_args *a,struct iovec *v,uint32_t n) {
 assert(!v && !n);if(create_failure)return EINVAL;
 assert(!global_resource);global_resource=calloc(1,sizeof(*global_resource));assert(global_resource);
 global_resource->res_id=a->handle;global_resource->fd_type=VIRGL_RESOURCE_FD_INVALID;
 pipe_resource=calloc(1,sizeof(*pipe_resource));assert(pipe_resource);pipe_resource->base.reference.count=1;pipe_resource->base.width0=16;pipe_resource->storage_bits=VREND_STORAGE_HOST_SYSTEM_MEMORY;pipe_resource->ptr=malloc(16);assert(pipe_resource->ptr);memset(pipe_resource->ptr,'A',16);
 global_resource->pipe_resource=&pipe_resource->base;
 return 0;
}
static int virgl_renderer_resource_create_blob(struct virgl_renderer_resource_create_blob_args *args) {struct virgl_renderer_resource_create_args a={.handle=args->res_handle};assert(!args->iovecs && !args->num_iovs);return virgl_renderer_resource_create(&a,NULL,0);}
static int virgl_renderer_resource_get_info(UNUSED unsigned id,struct virgl_renderer_resource_info *info) {info->fd=-1;return 0;}
#define ARRAY_SIZE(a) (sizeof(a)/sizeof((a)[0]))
#define CALLOC_STRUCT(t) calloc(1,sizeof(struct t))
#define FREE free
#define VREND_DEBUG(...) ((void)0)
#define has_feature(f) ((f)!=feat_timer_query)
#define VIRGL_QUERY_STATE_DONE 1
#include "query-defs.inc"
static uint32_t query_stats_index_to_gl_map[]={GL_SAMPLES_PASSED_ARB};
static void list_inithead(struct list_head *h) {h->next=h;h->prev=h;}
static void list_del(struct list_head *h) {h->prev->next=h->next;h->next->prev=h->prev;list_removed++;}
static struct vrend_resource *vrend_renderer_ctx_res_lookup(UNUSED void *ctx,uint32_t id) {return global_resource && global_resource->res_id==id?pipe_resource:NULL;}
#define vrend_report_context_error(...) ((void)0)
#define virgl_warn(...) ((void)0)
#define virgl_error(...) abort()
static void glGenQueries(UNUSED int n,GLuint *id) {*id=1;}
static void glDeleteQueries(UNUSED int n,UNUSED const GLuint *id) {}
static int vrend_renderer_object_insert(UNUSED struct vrend_context *ctx,struct vrend_query *q,UNUSED uint32_t h,UNUSED int type) {saved_query=q;return 1;}
static bool vrend_is_timer_query(unsigned type) {return type==GL_TIMESTAMP || type==GL_TIME_ELAPSED;}
static bool vrend_get_one_query_result(UNUSED unsigned id,UNUSED bool wide,uint64_t *result) {*result=42;return true;}
static void vrend_update_oq_samples_multiplier(UNUSED void *ctx) {abort();}
#include "query.inc"
#include "fill.inc"
#include "qemu.inc"
static void init(VirtIOGPU *g) {
 assert(!global_resource && !pipe_resource);for(unsigned i=0;i<alloc_count;i++)assert(!allocs[i].live);
 for(unsigned i=0;i<npages;i++){assert(!pages[i].live);assert(munmap(pages[i].p,4096)==0);}npages=alloc_count=0;
 maps=unmaps=arrays_freed=renderer_unrefs=responses=renderer_detaches=host_unmaps=wrapper_frees=pipe_destroyed=list_removed=stale_ledger=attach_calls=0;
 map_failure=-1;detach_injection=0;metadata_count=0;metadata_cleanup=false;create_failure=false;
 memset(g,0,sizeof(*g));TAILQ_INIT(&g->reslist);TAILQ_INIT(&g->gl.unmap_done_list);
 pipe_callbacks.attach_iov=vrend_pipe_resource_attach_iov;pipe_callbacks.detach_iov=vrend_pipe_resource_detach_iov;pipe_callbacks.unref=vrend_pipe_resource_unref;
}
static struct virtio_gpu_virgl_resource *create(VirtIOGPU *g,unsigned id) {
 struct virtio_gpu_resource_create_2d body={0};body.resource_id=id;body.width=16;body.height=1;
 struct iovec out={&body,sizeof(body)};struct virtio_gpu_ctrl_command cmd={.elem={&out,1}};
 virgl_cmd_create_resource_2d(g,&cmd);assert(!cmd.error);
 struct virtio_gpu_virgl_resource *r=virtio_gpu_virgl_find_resource(g,id);assert(r);tracked_wrapper=r;
 return r;
}
static struct iovec *observe(struct virtio_gpu_virgl_resource *r,unsigned *n) {
#ifdef BACKING_PATCHED
 *n=r->classic_iov_count;return r->classic_iov;
#else
 *n=r->base.iov_cnt;return r->base.iov;
#endif
}
static void attach(VirtIOGPU *g,unsigned id,unsigned len) {
 struct {struct virtio_gpu_resource_attach_backing body;struct virtio_gpu_mem_entry mem;} wire={0};wire.body.resource_id=id;wire.body.nr_entries=len?1:0;wire.mem.addr=0x1000;wire.mem.length=len;
 struct iovec out={&wire,sizeof(wire)};struct virtio_gpu_ctrl_command cmd={.elem={&out,1}};
 virgl_resource_attach_backing(g,&cmd);if(global_resource && global_resource->iov && !tracked_array)tracked_array=(void *)global_resource->iov;
 if(map_failure>=0 || metadata_count)check(cmd.error==VIRTIO_GPU_RESP_ERR_UNSPEC,"failed/invalid mapping returns existing UNSPEC");else check(!cmd.error,"attach preserves existing wire policy");
}
static void detach(VirtIOGPU *g,unsigned id) {struct virtio_gpu_resource_detach_backing body={0};body.resource_id=id;struct iovec out={&body,sizeof(body)};struct virtio_gpu_ctrl_command cmd={.elem={&out,1}};virgl_resource_detach_backing(g,&cmd);}
static struct virtio_gpu_ctrl_command *unref(VirtIOGPU *g,unsigned id) {struct virtio_gpu_resource_unref body={0};body.resource_id=id;struct iovec out={&body,sizeof(body)};struct virtio_gpu_ctrl_command *cmd=q_zero(sizeof(*cmd));cmd->elem.out_sg=&out;cmd->elem.out_num=1;bool suspended=false;virgl_cmd_resource_unref(g,cmd,&suspended);assert(!suspended);if(cmd->deferred)return cmd;q_free(cmd);return NULL;}
static void write_guest(char value) {assert(global_resource->iov);for(int i=0;i<global_resource->iov_count;i++)memset(global_resource->iov[i].iov_base,value,global_resource->iov[i].iov_len);}
static void conserved(const char *name) {check(maps==unmaps && arrays_freed==1 && !global_resource && !pipe_resource && wrapper_frees==1 && !stale_ledger,name);}
static void lifetime(VirtIOGPU *g,int path) {
 init(g);struct virtio_gpu_virgl_resource *r=create(g,7);attach(g,7,16);unsigned n;struct iovec *p=observe(r,&n);
 check(p==global_resource->iov && n==2,"successful attach ledger owns exact split P/N");check(r->base.iov==NULL && r->base.iov_cnt==0,"managed classic base has no second owner");
 check(pipe_resource->iov==global_resource->iov && pipe_resource->num_iovs==2,"actual global and pipe retain same P/N");
 char bytes[16];vrend_read_from_iovec(global_resource->iov,2,0,bytes,16);check(bytes[0]=='A' && bytes[15]=='A',"actual CUSTOM attach copies host A into split guest backing");write_guest('B');
 if(path==0){
#ifdef BACKING_PATCHED
  detach_classic_backing(r);check(r->classic_backing_state==CLASSIC_BACKING_DETACHED_RETAINED && !unmaps && r->classic_iov==p,"detach retains live owner until release");
  check(!global_resource->iov && !pipe_resource->iov && !memcmp(pipe_resource->ptr,"BBBBBBBBBBBBBBBB",16),"actual CUSTOM detach copies B before unmap and clears both layers");unsigned calls=renderer_detaches;detach_classic_backing(r);check(calls==renderer_detaches,"repeated retained detach is no-op");release_classic_backing(g,r);release_classic_backing(g,r);check(r->classic_backing_state==CLASSIC_BACKING_NONE && !r->classic_iov && !r->classic_iov_count,"release clears ledger once");
#else
  detach(g,7);
#endif
  detach(g,7);detach(g,7);unref(g,7);
 }else if(path==1)unref(g,7);
 else if(path==2)virtio_gpu_virgl_resource_destroy(g,&r->base,NULL);
 else {
#if VIRGL_VERSION_MAJOR >= 1
  struct virtio_gpu_virgl_hostmem_region *vmr=q_zero(sizeof(*vmr));vmr->g=g;vmr->res=r;vmr->mr.enabled=true;r->mr=&vmr->mr;
  struct virtio_gpu_ctrl_command *cmd=unref(g,7);check(cmd && cmd->deferred && !unmaps && !responses && !renderer_unrefs,"ordinary UNREF transfers command to MR deferred owner");
  check(r->unref_cmd==cmd && global_resource->iov && r->mr,"deferred owner retains mapping through grace seam");
  vmr->finish_unmapping=true;TAILQ_INSERT_TAIL(&g->gl.unmap_done_list,vmr,done_next);virtio_gpu_virgl_finish_unmap(g,vmr);
  check(responses==1 && host_unmaps==1,"actual finish_unmap completes command and host mapping once");
#else
  unref(g,7);
#endif
 }
 conserved(path==3?"deferred consumer leaves no stale ledger or mapping":"all cleanup consumers conserve one mapping owner");
}
static void failures_and_duplicate(VirtIOGPU *g) {
 init(g);struct virtio_gpu_virgl_resource *r=create(g,7);attach(g,7,16);struct iovec *old=(void *)global_resource->iov;unsigned n;
 attach(g,7,16);check(global_resource->iov==old && pipe_resource->iov==old && unmaps==2 && observe(r,&n)==old && n==2,"duplicate actual EINVAL frees only new mapping and preserves old ledger");unref(g,7);check(maps==unmaps,"duplicate mappings all unmapped exactly once");
 init(g);r=create(g,7);map_failure=2;attach(g,7,24);check(!global_resource->iov && !observe(r,&n) && maps==2 && unmaps==2,"partial map failure unwinds itself without caller double cleanup");map_failure=-1;unref(g,7);
 init(g);r=create(g,7);unsigned id=global_resource->res_id;global_resource->res_id=8;attach(g,7,16);check(!global_resource->iov && !observe(r,&n) && maps==unmaps,"missing renderer attach rejects and cleans new mapping only");global_resource->res_id=id;unref(g,7);
 init(g);r=create(g,7);attach(g,7,0);check(!global_resource->iov && !observe(r,&n),"NULL/0 attach leaves ledger NONE");attach(g,7,16);detach(g,7);unref(g,7);conserved("zero attach permits later nonempty attach");
#ifdef BACKING_PATCHED
 for(unsigned i=0;i<2;i++){init(g);r=create(g,7);metadata_count=i?UINT32_MAX:(uint32_t)INT_MAX+1;attach(g,7,0);check(metadata_cleanup && !global_resource->iov && !observe(r,&n),"metadata-only oversized count rejected before renderer narrowing");metadata_count=0;unref(g,7);}
#endif
}
static void query_lifetime(VirtIOGPU *g) {
 init(g);create(g,7);attach(g,7,16);struct vrend_sub_context sub={0};struct vrend_context ctx={&sub};
 assert(vrend_create_query(&ctx,1,PIPE_QUERY_TIMESTAMP,0,7,0)==0);check(saved_query->res==pipe_resource && pipe_resource->base.reference.count==2,"actual query retains resource ref without IOV snapshot");
 struct list_head waiting;list_inithead(&waiting);waiting.next=waiting.prev=&saved_query->waiting_queries;saved_query->waiting_queries.next=saved_query->waiting_queries.prev=&waiting;
 struct vrend_resource *held=pipe_resource;unref(g,7);check(!global_resource && held->base.reference.count==1 && !held->iov && !pipe_destroyed,"global UNREF preserves query ref after detach and unmap");
 check(vrend_check_query(saved_query) && ((struct virgl_host_query_state *)held->ptr)->query_state==VIRGL_QUERY_STATE_DONE,"late actual query writes private ptr with guest pages inaccessible");
 vrend_destroy_query(saved_query);saved_query=NULL;check(pipe_destroyed==1 && list_removed==1 && waiting.next==&waiting && waiting.prev==&waiting && maps==unmaps,"query destruction removes waiting entry and final resource ref");
}
static void nonclassic(VirtIOGPU *g,int path) {
 init(g);struct virtio_gpu_virgl_resource *r;
#if VIRGL_VERSION_MAJOR >= 1
 struct virtio_gpu_resource_create_blob blob={0};blob.resource_id=7;blob.blob_mem=VIRTIO_GPU_BLOB_MEM_HOST3D;blob.size=16;
 struct iovec out={&blob,sizeof(blob)};struct virtio_gpu_ctrl_command cmd={.elem={&out,1}};
 virgl_cmd_resource_create_blob(g,&cmd);assert(!cmd.error);r=virtio_gpu_virgl_find_resource(g,7);assert(r);tracked_wrapper=r;
#else
 r=create(g,7); /* old-version structural nonmanaged seam, no CREATE_BLOB */
#endif
#ifdef BACKING_PATCHED
#if VIRGL_VERSION_MAJOR < 1
 r->classic_backing_managed=false;
#endif
 check(!r->classic_backing_managed,"actual blob CREATE does not acquire classic ledger");
#endif
 attach(g,7,16);r->base.iov=(void *)global_resource->iov;r->base.iov_cnt=2;
 if(path==0)virtio_gpu_virgl_resource_destroy(g,&r->base,NULL);
 else {
#if VIRGL_VERSION_MAJOR >= 1
  struct virtio_gpu_virgl_hostmem_region *vmr=q_zero(sizeof(*vmr));vmr->g=g;vmr->res=r;vmr->mr.enabled=true;r->mr=&vmr->mr;assert(unref(g,7));vmr->finish_unmapping=true;TAILQ_INSERT_TAIL(&g->gl.unmap_done_list,vmr,done_next);virtio_gpu_virgl_finish_unmap(g,vmr);check(responses==1,"existing nonmanaged deferred response remains once");
#else
  unref(g,7);
#endif
 }
 conserved("nonclassic existing ownership branch remains intact");
}
static void create3_and_hostmem_destroy(VirtIOGPU *g) {
 init(g);
 struct virtio_gpu_resource_create_3d body={0};body.resource_id=7;body.width=16;body.height=1;
 struct iovec out={&body,sizeof(body)};struct virtio_gpu_ctrl_command cmd={.elem={&out,1}};
 virgl_cmd_create_resource_3d(g,&cmd);assert(!cmd.error);
 struct virtio_gpu_virgl_resource *r=virtio_gpu_virgl_find_resource(g,7);assert(r);tracked_wrapper=r;
#ifdef BACKING_PATCHED
 check(r->classic_backing_managed && r->classic_backing_state==CLASSIC_BACKING_NONE && !r->classic_iov && !r->classic_iov_count,"successful 3D CREATE publishes zeroed classic marker");
#endif
 attach(g,7,16);unref(g,7);conserved("3D CREATE mapping has same classic owner");
#if VIRGL_VERSION_MAJOR >= 1
 for(int stage=0;stage<3;stage++){
  init(g);r=create(g,7);attach(g,7,16);
  struct virtio_gpu_virgl_hostmem_region *vmr=q_zero(sizeof(*vmr));vmr->g=g;vmr->res=r;vmr->mr.enabled=true;r->mr=&vmr->mr;
  vmr->unmapping=stage>0;vmr->finish_unmapping=stage==2;
  if(stage==2)TAILQ_INSERT_TAIL(&g->gl.unmap_done_list,vmr,done_next);
  r->unref_cmd=q_zero(sizeof(*r->unref_cmd));r->map_blocked=true;g->parent_obj.renderer_blocked=1;
  virtio_gpu_virgl_resource_destroy(g,&r->base,NULL);
  check(!responses && g->parent_obj.renderer_blocked==0,"hostmem destroy cancels deferred command without reset success response");
  if(stage<2){check(!vmr->g && vmr->parent_obj.free!=NULL,"existing MR finalizer owns pending region storage");q_free(vmr);}
  conserved("hostmem destroy states preserve classic mapping owner");
 }
#endif
}
static void broken(VirtIOGPU *g,int injection) {
#ifdef BACKING_PATCHED
 init(g);create(g,7);attach(g,7,16);pid_t pid=fork();assert(pid>=0);
 if(!pid){invariant_child=true;detach_injection=injection;if(injection==7)actual_cleanup_mapping_iov(g,(void *)global_resource->iov,global_resource->iov_count);if(injection==5)global_resource->res_id=8;detach(g,7);_exit(88);}
 int status;assert(waitpid(pid,&status,0)==pid);
 if(injection==7)check(WIFEXITED(status) && WEXITSTATUS(status)==90,"forbidden cleanup seam cannot masquerade as production fail-stop");
 else check(WIFSIGNALED(status) && WTERMSIG(status)==SIGABRT,"broken host contract fail-stops release build before cleanup or response");
 detach_injection=0;
#ifdef BACKING_EARLY_CLEANUP
 /* Test teardown follows the unmutated renderer/cleanup chain after observing
  * the child's rejected ordering. It does not repair the mutant handler. */
 struct iovec *v=NULL;int n=0;actual_renderer_detach_iov(7,&v,&n);actual_cleanup_mapping_iov(g,v,n);
 tracked_wrapper->classic_iov=NULL;tracked_wrapper->classic_iov_count=0;tracked_wrapper->classic_backing_state=CLASSIC_BACKING_NONE;
#else
 detach(g,7);
#endif
 unref(g,7);
#else
 (void)g;(void)injection;
#endif
}
static void pipe_noop(VirtIOGPU *g) {init(g);create(g,7);attach(g,7,16);pipe_callbacks.detach_iov=no_pipe_detach;struct iovec *p=NULL;int n=0;actual_renderer_detach_iov(7,&p,&n);check(!global_resource->iov && pipe_resource->iov==p,"pipe no-op injection exposes private retained pointer beyond QEMU output check");pipe_callbacks.detach_iov=vrend_pipe_resource_detach_iov;vrend_pipe_resource_detach_iov(&pipe_resource->base,NULL);actual_cleanup_mapping_iov(g,p,n);
#ifdef BACKING_PATCHED
 tracked_wrapper->classic_iov=NULL;tracked_wrapper->classic_iov_count=0;tracked_wrapper->classic_backing_state=CLASSIC_BACKING_NONE;
#endif
 unref(g,7);}
int main(void) {VirtIOGPU g={0};
#ifdef BACKING_EARLY_CLEANUP
 broken(&g,1);
#else
 for(int i=0;i<4;i++)lifetime(&g,i);failures_and_duplicate(&g);query_lifetime(&g);nonclassic(&g,0);nonclassic(&g,1);create3_and_hostmem_destroy(&g);for(int i=1;i<=7;i++)broken(&g,i);pipe_noop(&g);
#endif
 init(&g);printf("%d checks, %d failures; actual mapping, renderer CUSTOM, cleanup and query consumers\n",checks,failures);return failures?1:0;}
