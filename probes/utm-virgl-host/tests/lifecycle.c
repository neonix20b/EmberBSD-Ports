#if defined(LIFECYCLE_RENDERER)
/* SPDX-License-Identifier: BSD-2-Clause. External GL/list/winsys seams. */
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <string.h>
#include <unistd.h>
#define VIRGL_RENDERER_UNSTABLE_APIS
#include "virglrenderer.h"
#define TRACE_FUNC() ((void)0)
#define UNUSED __attribute__((unused))
#define virgl_warn(...) ((void)0)
#define virgl_error(...) ((void)0)
#ifdef NDEBUG
#undef assert
#define assert(e) ((e)?(void)0:abort())
#endif
static unsigned failures,checks,queries,init_calls,wrapper_allocs,wrapper_frees,gbm_allocs,gbm_frees,terminations;
static void check(bool e,const char *s){checks++;if(!e){failures++;fprintf(stderr,"FAIL %s\n",s);}}
struct list_head {struct list_head *next,*prev;};
static void list_inithead(struct list_head *h){h->next=h->prev=h;}
static bool list_is_empty(struct list_head *h){return h->next==h;}
static void list_del(struct list_head *h){h->prev->next=h->next;h->next->prev=h->prev;}
static void list_delinit(struct list_head *h){list_del(h);list_inithead(h);}
static void list_addtail(struct list_head *e,struct list_head *h){e->prev=h->prev;e->next=h;h->prev->next=e;h->prev=e;}
#define list_for_each_entry_safe(t,v,h,m) for(struct list_head *it=(h)->next,*next;it!=(h) && (next=it->next,true);it=next) for(t *v=(t*)((char*)it - offsetof(t,m));v;v=NULL)
struct vrend_context {int ctx_id;void(*fence_retire)(uint64_t,void*);void *fence_retire_data;};
struct vrend_query {struct vrend_context *ctx;int sub_ctx_id;unsigned id;struct list_head waiting_queries;bool done;};
struct vrend_fence {struct vrend_context *ctx;uint64_t fence_id;struct list_head fences;};
static struct {bool use_async_fence_cb,sync_thread,polling;atomic_bool has_waiting_queries;int eventfd,fence_mutex,poll_mutex,poll_cond;struct list_head fence_list,waiting_query_list;}vrend_state;
static void flush_eventfd(int f){(void)f;abort();}
static void mtx_lock(int *f){(void)f;abort();}
static void mtx_unlock(int *f){(void)f;abort();}
static void cnd_signal(int *f){(void)f;abort();}
static void free_fence_locked(struct vrend_fence *f){list_del(&f->fences);}
static bool need_fence_retire_signal_locked(struct vrend_fence *f,struct list_head *l){(void)f;(void)l;return true;}
static bool do_wait(struct vrend_fence *f,bool block){(void)f;(void)block;return true;}
static void vrend_renderer_force_ctx_0(void){}
static bool vrend_hw_switch_context_with_sub(struct vrend_context *c,int id){(void)c;(void)id;return true;}
static bool vrend_check_query(struct vrend_query *q){queries++;q->done=true;return true;}
struct virgl_context {};
struct virgl_context_foreach_args {bool(*callback)(struct virgl_context*,void*);};
static bool virgl_context_foreach_retire_fences(struct virgl_context *c,void *p){(void)c;(void)p;return true;}
static void virgl_context_foreach(struct virgl_context_foreach_args *a){(void)a;}
#define TRACE_INIT() (init_calls++)
#include "renderer-state.inc"
static struct global_state state;
static bool eventfd_available;
static unsigned init_renderer_flags;
static bool has_eventfd(void){return eventfd_available;}
static bool has_fence_pipe(void){return true;}
struct virgl_resource_pipe_callbacks {int x;};
static const struct virgl_resource_pipe_callbacks *vrend_renderer_get_pipe_callbacks(void){static struct virgl_resource_pipe_callbacks c;return &c;}
static int virgl_resource_table_init(const struct virgl_resource_pipe_callbacks *c){(void)c;return 0;}
static int virgl_context_table_init(void){return 0;}
static int vrend_winsys_init(int f,int d){(void)f;(void)d;abort();}
int vrend_winsys_init_external(void*);
static int vrend_cbs,proxy_cbs;
static int vrend_renderer_init(void *c,unsigned f){(void)c;init_renderer_flags=f;return 0;}
static int proxy_renderer_init(void *c,int f){(void)c;(void)f;abort();}
static int drm_renderer_init(int fd){(void)fd;abort();}
static int virgl_fence_table_init(void){return 0;}
void virgl_renderer_cleanup(void *c){(void)c;memset(&state,0,sizeof(state));}
#include "renderer-flags.inc"
#include "renderer-init.inc"
#include "renderer-functions.inc"
static void fence(void *p,uint32_t f){(void)p;(void)f;}
static void context_fence(void *p,uint32_t c,uint32_t r,uint64_t f){(void)p;(void)c;(void)r;(void)f;}
static void *create(void *p,int s,struct virgl_renderer_gl_ctx_param *q){(void)p;(void)s;(void)q;return (void*)1;}
static void destroy(void *p,void *c){(void)p;(void)c;}
static int current(void *p,int i,void *c){(void)p;(void)i;(void)c;return 0;}
#define HAVE_EPOXY_EGL_H 1
struct virgl_gbm {int x;};struct virgl_egl {void *egl_display;struct virgl_gbm *gbm;};
typedef void *EGLDisplay;
#define EGL_EXTENSIONS 1
static struct virgl_egl *egl;
static struct virgl_gbm *gbm;
enum {CONTEXT_NONE,CONTEXT_EGL,CONTEXT_GLX,CONTEXT_EGL_EXTERNAL};
static int use_context;
static struct virgl_gbm *virgl_gbm_init(int fd){(void)fd;gbm_allocs++;return calloc(1,sizeof(*gbm));}
static void virgl_gbm_fini(struct virgl_gbm *g){gbm_frees++;free(g);}
static const char *eglQueryString(void *p,int name){(void)p;(void)name;return "extensions";}
static bool virgl_egl_add_extensions(struct virgl_egl *e,const char *s){(void)e;(void)s;return true;}
static bool virgl_egl_check_extensions(struct virgl_egl *e){(void)e;return true;}
static void virgl_egl_win32_init(struct virgl_egl *e){(void)e;}
static void virgl_egl_metal_init(struct virgl_egl *e){(void)e;}
static void virgl_egl_destroy(struct virgl_egl *e){terminations++;free(e);}
static void counted_free(void *p){if(p)wrapper_frees++;free(p);}
static void *counted_calloc(size_t n,size_t z){wrapper_allocs++;return calloc(n,z);}
#define free counted_free
#define calloc counted_calloc
#include "winsys-functions.inc"
#undef free
#undef calloc
int main(void){
 struct vrend_context ctx={0};struct vrend_query q={.ctx=&ctx};list_inithead(&vrend_state.fence_list);list_inithead(&vrend_state.waiting_query_list);list_addtail(&q.waiting_queries,&vrend_state.waiting_query_list);vrend_state.has_waiting_queries=true;state.vrend_initialized=true;virgl_renderer_poll();check(q.done&&queries==1&&!vrend_state.has_waiting_queries,"empty-fence poll completes pending query");
 for(int i=0;i<2;i++){check(vrend_winsys_init_external((void*)1)==0,"external EGL init");vrend_winsys_cleanup();check(!egl&&!gbm&&use_context==CONTEXT_NONE&&wrapper_frees==wrapper_allocs&&!terminations&&gbm_allocs==gbm_frees,"external EGL cleanup owns wrapper and GBM, never display");}
#ifndef BASELINE
 struct virgl_renderer_callbacks c={.version=3,.write_fence=fence,.write_context_fence=context_fence,.create_gl_context=create,.destroy_gl_context=destroy,.make_current=current};
#ifdef ENABLE_VIDEO
 check(virgl_renderer_ember_classic_init_v1((void*)1,0,&c)==-ENOTSUP&&init_calls==0,"video build rejects before init");
#else
  for(unsigned available=0;available<2;available++) {
   memset(&state,0,sizeof(state));eventfd_available=available;
   check(virgl_renderer_ember_classic_init_v1((void*)1,VIRGL_RENDERER_NATIVE_SHARE_TEXTURE,&c)==0 && init_renderer_flags==VREND_NATIVE_SHARE_TEXTURE,"actual init never creates worker for forced eventfd true/false");
 }
 init_calls=1;
 check(virgl_renderer_ember_classic_init_v1((void*)1,VIRGL_RENDERER_THREAD_SYNC,&c)==-EINVAL&&init_calls==1,"downstream ABI rejects worker flag before init");state.client_initialized=true;check(virgl_renderer_ember_classic_init_v1((void*)1,0,&c)==-EBUSY&&init_calls==1,"downstream ABI rejects live reinit");state.client_initialized=false;c.write_context_fence=NULL;check(virgl_renderer_ember_classic_init_v1((void*)1,0,&c)==-EINVAL&&init_calls==1,"downstream ABI requires context completion");
#endif
#endif
 printf("renderer: %u checks, %u failures\n",checks,failures);return failures?1:0;}

#elif defined(LIFECYCLE_BASELINE_RESET)
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <sys/queue.h>
#include <sys/uio.h>
#include <stddef.h>
#define VIRGL_VERSION_MAJOR 0
#define container_of(p,t,m) ((t*)((char*)(p)-offsetof(t,m)))
typedef void MemoryRegion;
#define QTAILQ_FOREACH_SAFE TAILQ_FOREACH_SAFE
#define QTAILQ_FIRST TAILQ_FIRST
#define QTAILQ_REMOVE TAILQ_REMOVE
#define QTAILQ_EMPTY TAILQ_EMPTY
#define VIRTIO_GPU(g) ((VirtIOGPU *)(g))
#define VIRTIO_GPU_BASE(g) (&((VirtIOGPU *)(g))->parent_obj)
#define VIRTIO_GPU_GL(g) (&((VirtIOGPU *)(g))->gl)
#define VIRTIO_GPU_GET_CLASS(g) (&klass)
#define OBJECT(g) (g)
#define g_free free
typedef void Error; typedef void VirtIODevice;
struct virtio_gpu_simple_resource {unsigned resource_id;struct iovec *iov;unsigned iov_cnt; TAILQ_ENTRY(virtio_gpu_simple_resource) next;};
struct virtio_gpu_ctrl_command {TAILQ_ENTRY(virtio_gpu_ctrl_command) next;};
#define QTAILQ_ENTRY TAILQ_ENTRY
#include "red-shape.inc"
typedef struct {int renderer_state;} VirtIOGPUGL;
enum {RS_START,RS_INIT_FAILED,RS_INITED,RS_RESET};
typedef struct VirtIOGPU { struct {struct {int max_outputs;}conf;struct {void *con;}scanout[1];}parent_obj; VirtIOGPUGL gl; TAILQ_HEAD(,virtio_gpu_simple_resource)reslist; TAILQ_HEAD(,virtio_gpu_ctrl_command)cmdq,fenceq; bool reset_finished;int reset_cond,inflight;void *reset_bh;} VirtIOGPU;
static unsigned detached,unmapped; static bool violated;
static struct virtio_gpu_virgl_resource *resources[2];
static void error_report(const char *s){fprintf(stderr,"%s\n",s);}
static void virgl_renderer_resource_detach_iov(unsigned id,struct iovec **v,int *n){detached++;*v=resources[id]->classic_iov;*n=resources[id]->classic_iov_count;}
static void virtio_gpu_cleanup_mapping_iov(VirtIOGPU *g,struct iovec *v,unsigned n){(void)g;(void)n;if(detached<2)violated=true;unmapped++;free(v);}
static void virgl_renderer_resource_unref(unsigned id){(void)id;}
static void virtio_gpu_resource_destroy(VirtIOGPU *g,struct virtio_gpu_simple_resource *r,Error **e){(void)e;TAILQ_REMOVE(&g->reslist,r,next);free(r);}
#include "red-destroy.inc"
static struct {void(*resource_destroy)(VirtIOGPU *,struct virtio_gpu_simple_resource *,Error **);}klass={virtio_gpu_virgl_resource_destroy};
typedef typeof(klass) VirtIOGPUClass;
#define error_append_hint(...) ((void)0)
#define error_report_err(e) ((void)(e))
static void dpy_gfx_replace_surface(void *c,void *s){(void)c;(void)s;}
static void qemu_cond_signal(void *c){(void)c;}
static bool qemu_in_vcpu_thread(void){return false;}
static void qemu_bh_schedule(void *p){(void)p;}
static void qemu_cond_wait_bql(void *p){(void)p;abort();}
static void virtio_gpu_base_reset(void *p){(void)p;}
static void virtio_gpu_virgl_reset_scanout(VirtIOGPU *g){(void)g;}
static void virtio_gpu_reset_bh(void *);
static void aio_bh_call(void *p){virtio_gpu_reset_bh(p);}
#include "reset-red.inc"
int main(void){VirtIOGPU g={0};TAILQ_INIT(&g.reslist);TAILQ_INIT(&g.cmdq);TAILQ_INIT(&g.fenceq);g.gl.renderer_state=RS_INITED;g.reset_bh=&g;for(int i=0;i<2;i++){struct virtio_gpu_virgl_resource *r=calloc(1,sizeof(*r));resources[i]=r;r->base.resource_id=i;r->classic_backing_managed=true;r->classic_backing_state=CLASSIC_BACKING_ATTACHED;r->classic_iov=calloc(1,sizeof(struct iovec));r->classic_iov_count=1;TAILQ_INSERT_TAIL(&g.reslist,&r->base,next);}virtio_gpu_gl_reset(&g);if(violated){fputs("FAIL release before final detach\n",stderr);return 1;}return 0;}

#else
/* SPDX-License-Identifier: BSD-2-Clause
 * EmberBSD, AI-assisted lifecycle causal harness. Actual bodies are extracted.
 * BQL/BH/timer scheduler, DMA/display/GL and command payload consumers are seams.
 * This does not prove native serialization, GL lifetime or guest no-touch.
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
#ifdef NDEBUG
#undef assert
#define assert(x) ((x)?(void)0:(fprintf(stderr,"observer failure: %s\n",#x),abort()))
#endif
#include "virglrenderer.h"
#ifdef LIFECYCLE_NO_ABI
#undef VIRGL_RENDERER_EMBER_CLASSIC_LIFECYCLE_ABI
#endif
#define VIRGL_CHECK_VERSION(a,b,c) 1
#define QTAILQ_HEAD TAILQ_HEAD
#define QTAILQ_ENTRY TAILQ_ENTRY
#define QTAILQ_INIT TAILQ_INIT
#define QTAILQ_FIRST TAILQ_FIRST
#define QTAILQ_EMPTY TAILQ_EMPTY
#define QTAILQ_FOREACH TAILQ_FOREACH
#define QTAILQ_FOREACH_SAFE TAILQ_FOREACH_SAFE
#define QTAILQ_INSERT_TAIL TAILQ_INSERT_TAIL
#define QTAILQ_REMOVE TAILQ_REMOVE
#define QSLIST_HEAD SLIST_HEAD
#define QSLIST_ENTRY SLIST_ENTRY
#define QSLIST_INIT SLIST_INIT
#define QSLIST_FIRST SLIST_FIRST
#define QSLIST_EMPTY SLIST_EMPTY
#define QSLIST_REMOVE_HEAD SLIST_REMOVE_HEAD
#define QSLIST_INSERT_HEAD_ATOMIC SLIST_INSERT_HEAD
#define QSLIST_MOVE_ATOMIC(d,s) do {(d)->slh_first=(s)->slh_first;SLIST_INIT(s);}while(0)
#define container_of(p,t,m) ((t*)((char*)(p)-offsetof(t,m)))
#define VIRTIO_GPU(g) ((VirtIOGPU*)(g))
#define VIRTIO_GPU_GL(g) ((VirtIOGPUGL*)(g))
#define VIRTIO_GPU_BASE(g) (&VIRTIO_GPU(g)->parent_obj)
#define VIRTIO_DEVICE(g) ((VirtIODevice*)(g))
#define DEVICE(g) (g)
#define OBJECT(g) (g)
#define VIRTIO_GPU_GET_CLASS(g) (&klass)
#define QEMU_CLOCK_VIRTUAL 0
#define LOG_GUEST_ERROR 1
#define qemu_log_mask(...) ((void)0)
#define error_append_hint(...) ((void)0)
#define error_report_err(...) ((void)0)
#define trace_virtio_gpu_fence_resp(...) ((void)0)
#define trace_virtio_gpu_fence_ctrl(...) ((void)0)
#define trace_virtio_gpu_dec_inflight_fences(...) ((void)0)
#define trace_virtio_gpu_inc_inflight_fences(...) ((void)0)
#define trace_virtio_gpu_cmd_suspended(...) ((void)0)
#define trace_virtio_gpu_cmd_ctx_create(...) ((void)0)
#define VIRTIO_GPU_FLAG_FENCE 1
#define VIRTIO_GPU_FLAG_INFO_RING_IDX 2
#define VIRTIO_GPU_F_CONTEXT_INIT 4
#define VIRTIO_GPU_RESP_ERR_UNSPEC 0x1200
#define VIRTIO_GPU_RESP_ERR_INVALID_PARAMETER 0x1205
#define VIRTIO_GPU_RESP_OK_NODATA 0x1100
#define VIRTIO_GPU_RESP_OK_CAPSET 0x1103
#include "tokens.inc"
typedef struct VirtIOGPU VirtIOGPU;
typedef struct VirtIOGPUGL VirtIOGPUGL;
typedef struct VirtIOGPU VirtIODevice;
typedef struct VirtIOGPU DeviceState;
typedef void Error; static Error *error_abort;
typedef void MemoryRegion;
typedef void pixman_image_t;typedef void *qemu_pixman_shareable;
typedef struct {struct iovec *out_sg;unsigned out_num;} VirtQueueElement;
typedef struct {struct virtio_gpu_ctrl_command *pop;} VirtQueue;
struct virtio_gpu_ctrl_hdr {uint32_t type,flags;uint64_t fence_id;uint32_t ctx_id;uint8_t ring_idx,padding[3];};
struct virtio_gpu_ctx_create {struct virtio_gpu_ctrl_hdr hdr;uint32_t nlen,context_init;char debug_name[64];};
struct virtio_gpu_get_capset {struct virtio_gpu_ctrl_hdr hdr;uint32_t capset_id,capset_version;};
struct virtio_gpu_resp_capset {struct virtio_gpu_ctrl_hdr hdr;char capset_data[];};
#include "command.inc"
#include "resource.inc"
#include "ledger-shape.inc"
typedef struct Handle {void(*fn)(void*);void *opaque;bool scheduled;bool timer;} QEMUBH;
typedef QEMUBH QEMUTimer;
static unsigned allocated_handles,deleted_handles,detaches,unmaps,cleanup_calls,renderer_calls,responses,freed_commands,dispatches,forced,query_polls;
static bool native_live;
static unsigned fail_count,check_count,expected_detaches;
static bool premature,oom,inject_fault,inject_display_block,inject_poll,inject_fence,reenter,init_fails,init_oom,invariant_child,block_child,vcpu,ordering_child,stats_requested,mismatch_child;
static void check(bool ok,const char *msg){check_count++;if(!ok){fail_count++;fprintf(stderr,"FAIL %s\n",msg);}}
static QEMUBH *new_handle(void(*fn)(void*),void *p){QEMUBH *h=calloc(1,sizeof(*h));assert(h);h->fn=fn;h->opaque=p;allocated_handles++;return h;}
#define virtio_bh_io_new_guarded(d,f,p) new_handle(f,p)
static void qemu_bh_schedule(QEMUBH *h){assert(h);h->scheduled=true;}
static void qemu_bh_cancel(QEMUBH *h){assert(h);h->scheduled=false;}
static void qemu_bh_delete(QEMUBH *h){if(block_child)_exit(90);assert(h);deleted_handles++;free(h);}
static void aio_bh_call(QEMUBH *h){h->scheduled=false;h->fn(h->opaque);}
static QEMUTimer *timer_new_ms(int c,void(*f)(void*),void *p){(void)c;QEMUTimer *t=new_handle(f,p);t->timer=true;return t;}
static void timer_del(QEMUTimer *t){assert(t);t->scheduled=false;}
static void timer_free(QEMUTimer *t){qemu_bh_delete(t);}
static void timer_mod(QEMUTimer *t,uint64_t time){(void)time;qemu_bh_schedule(t);}
static uint64_t qemu_clock_get_ms(int c){(void)c;return 0;}
typedef struct {unsigned len;uint32_t data[4];} GArray;
#define g_array_index(a,t,i) ((a)->data[i])
struct virtio_gpu_scanout {void *con;struct {uint32_t width,height;uint32_t data[4];} *current_cursor;};
typedef struct {int renderer_blocked;struct {unsigned max_outputs;bool stats,venus,neptune,context,blob,uuid,dmabuf;unsigned flags;uint64_t hostmem;}conf;struct {unsigned num_capsets;}virtio_config;struct virtio_gpu_scanout scanout[2];} VirtIOGPUBase;
struct VirtIOGPU {VirtIOGPUBase parent_obj;TAILQ_HEAD(,virtio_gpu_simple_resource)reslist;TAILQ_HEAD(,virtio_gpu_ctrl_command)cmdq,fenceq;struct {TAILQ_HEAD(,virtio_gpu_simple_resource)bufs;}dmabuf;bool processing_cmdq,reset_finished,negotiated;unsigned inflight;struct {unsigned requests,max_inflight,req_3d,bytes_3d;}stats;QEMUBH *ctrl_bh,*reset_bh;int reset_cond;GArray *capset_ids;};
typedef enum {RS_START,RS_INIT_FAILED,RS_INITED,RS_RESET} RenderState;
#include "state.inc"
#include "gl-shape.inc"
struct virtio_gpu_virgl_hostmem_region {TAILQ_ENTRY(virtio_gpu_virgl_hostmem_region) next;};
typedef struct {bool(*cmdq_allowed)(VirtIOGPU*);bool(*cmdq_handoff_allowed)(VirtIOGPU*);bool(*reset_resources)(VirtIOGPU*);void(*process_cmd)(VirtIOGPU*,struct virtio_gpu_ctrl_command*);void(*resource_destroy)(VirtIOGPU*,struct virtio_gpu_simple_resource*,Error**);} VirtIOGPUClass;
static VirtIOGPUClass klass;
static void error_report(const char *s,...){fprintf(stderr,"diagnostic: %s\n",s);}
#define virtio_gpu_stats_enabled(c) ((c).stats)
#define virtio_gpu_venus_enabled(c) ((c).venus)
#define virtio_gpu_neptune_enabled(c) ((c).neptune)
#define virtio_gpu_context_init_enabled(c) ((c).context)
static bool virtio_vdev_has_feature(VirtIODevice *v,unsigned f){(void)f;return v->negotiated;}
static bool qemu_in_vcpu_thread(void){return vcpu;}
static void qemu_cond_signal(void *p){(void)p;}
static void qemu_cond_wait_bql(void *p){VirtIOGPU *g=container_of(p,VirtIOGPU,reset_cond);aio_bh_call(g->reset_bh);}
static void virtio_gpu_base_reset(VirtIOGPUBase *b){(void)b;}
static void *q_try(size_t n){return oom?NULL:calloc(1,n);}
#define g_try_new(t,n) ((t*)q_try(sizeof(t)*(n)))
#define g_new(t,n) ((t*)calloc(n,sizeof(t)))
#define g_malloc0 calloc_one
static void *calloc_one(size_t n){return calloc(1,n);}
static void q_free(void *p){free(p);}
#define g_free q_free
static size_t iov_to_buf(struct iovec *v,unsigned n,size_t off,void *p,size_t len){if(!n||off>=v[0].iov_len)return 0;size_t count=v[0].iov_len-off;if(count>len)count=len;memcpy(p,(char*)v[0].iov_base+off,count);return count;}
static void virtio_gpu_ctrl_response_nodata(VirtIOGPU *g,struct virtio_gpu_ctrl_command *c,uint32_t error){(void)g;(void)error;if(invariant_child||mismatch_child)_exit(90);if(detaches<expected_detaches)premature=true;assert(!c->finished);c->finished=true;responses++;}
static void virtio_gpu_ctrl_response(VirtIOGPU *g,struct virtio_gpu_ctrl_command *c,struct virtio_gpu_ctrl_hdr *h,size_t n){(void)n;virtio_gpu_ctrl_response_nodata(g,c,h->type);}
static void dpy_gfx_replace_surface(void *c,void *s){(void)c;(void)s;if(block_child)_exit(90);renderer_calls++;}
static void dpy_gl_scanout_disable(void *c){(void)c;if(block_child)_exit(90);renderer_calls++;}
static void virtio_gpu_cleanup_mapping_iov(VirtIOGPU *g,struct iovec *v,uint32_t n){(void)g;(void)n;if(invariant_child||mismatch_child)_exit(90);if(detaches<expected_detaches){premature=true;if(ordering_child)_exit(90);}unmaps++;free(v);}
static struct virtio_gpu_virgl_resource *resources[3];
void virgl_renderer_resource_detach_iov(int id,struct iovec **v,int *n){if(invariant_child)_exit(90);struct virtio_gpu_virgl_resource *r=resources[id-1];detaches++;*v=r->classic_iov;*n=(mismatch_child&&id==2)?-1:(int)r->classic_iov_count;}
void virgl_renderer_cleanup(void *p){(void)p;if(block_child)_exit(90);cleanup_calls++;native_live=false;}
static void virtio_gpu_virgl_resource_destroy(VirtIOGPU *g,struct virtio_gpu_simple_resource *r,Error **e){(void)e;if(block_child)_exit(90);struct virtio_gpu_virgl_resource *v=container_of(r,struct virtio_gpu_virgl_resource,base);assert(v->classic_backing_state==CLASSIC_BACKING_NONE);TAILQ_REMOVE(&g->reslist,r,next);free(r);renderer_calls++;}
static void virtio_gpu_virgl_finish_unmap(VirtIOGPU *g,struct virtio_gpu_virgl_hostmem_region *r){(void)g;(void)r;abort();}
static void virtio_gpu_virgl_reset(VirtIOGPU *g){(void)g;abort();}
static bool virtio_queue_ready(VirtQueue *v){(void)v;return true;}
static struct virtio_gpu_ctrl_command *virtqueue_pop(VirtQueue *v,size_t size){(void)size;struct virtio_gpu_ctrl_command *c=v->pop;v->pop=NULL;return c;}
#include "fill.inc"
#include "protos.inc"
void virtio_gpu_process_cmdq(VirtIOGPU*);
void virtio_gpu_reset(VirtIODevice*);
static void virtio_gpu_reset_bh(void*);
static void virgl_create_context_dummy(void){}
static virgl_renderer_gl_context virgl_create_context(void *p,int i,struct virgl_renderer_gl_ctx_param *v){(void)p;(void)i;(void)v;return (void*)1;}
static void virgl_destroy_context(void *p,virgl_renderer_gl_context c){(void)p;(void)c;}
static int virgl_make_context_current(void *p,int i,virgl_renderer_gl_context c){(void)p;(void)i;(void)c;return 0;}
static void *qemu_egl_display=(void*)1,*qemu_egl_angle_native_device=(void*)1;
static void *virgl_get_egl_display(void *p){(void)p;return qemu_egl_display;}
#include "defaults.inc"
static struct virgl_renderer_callbacks virtio_gpu_3d_cbs;
static unsigned init_flags,init_calls;
int virgl_renderer_init(void *p,int flags,struct virgl_renderer_callbacks *c){(void)p;(void)flags;(void)c;abort();}
int virgl_renderer_ember_classic_init_v1(void *p,int flags,struct virgl_renderer_callbacks *c){assert(!native_live);init_calls++;init_flags=flags;assert(c->version>=3);if(init_oom){oom=true;c->write_fence(p,1);oom=false;}if(init_fails)return -EINVAL;native_live=true;return 0;}
static VirtIOGPU *active_g;
void virgl_renderer_poll(void){query_polls++;if(inject_poll){virgl_write_async_fence(active_g,1);}}
void virgl_renderer_force_ctx_0(void){forced++;}
int virgl_renderer_create_fence(int fence,uint32_t type){(void)type;if(inject_fence){virgl_write_async_fence(active_g,(uint32_t)fence);if(reenter)virtio_gpu_virgl_async_fence_bh(active_g);}return 0;}
int virgl_renderer_context_create_fence(uint32_t c,uint32_t f,uint32_t q,uint64_t id){(void)f;virgl_write_async_context_fence(active_g,c,(uint32_t)q,id);return 0;}
int virgl_renderer_context_create(uint32_t id,uint32_t len,const char *name){(void)id;(void)len;(void)name;renderer_calls++;return 0;}
int virgl_renderer_context_create_with_flags(uint32_t id,uint32_t flags,uint32_t len,const char *name){(void)flags;return virgl_renderer_context_create(id,len,name);}
void virgl_renderer_get_cap_set(uint32_t id,uint32_t *ver,uint32_t *size){(void)id;renderer_calls++;*ver=1;*size=4;}
void virgl_renderer_fill_caps(uint32_t id,uint32_t ver,void *caps){(void)id;(void)ver;(void)caps;renderer_calls++;}
void *virgl_renderer_get_cursor_data(uint32_t id,uint32_t *w,uint32_t *h){(void)id;(void)w;(void)h;renderer_calls++;return NULL;}
static void dispatch(VirtIOGPU *g,struct virtio_gpu_ctrl_command *c){dispatches++;if(inject_display_block)g->parent_obj.renderer_blocked=1;if(inject_fault)virtio_gpu_virgl_request_fault(g,c,VIRTIO_GPU_RESP_ERR_INVALID_PARAMETER);}
#define STUB(n) static void n(VirtIOGPU *g,struct virtio_gpu_ctrl_command *c){dispatch(g,c);}
STUB(virgl_cmd_context_destroy) STUB(virgl_cmd_create_resource_2d) STUB(virgl_cmd_create_resource_3d) STUB(virgl_cmd_submit_3d) STUB(virgl_cmd_transfer_to_host_2d) STUB(virgl_cmd_transfer_to_host_3d) STUB(virgl_cmd_transfer_from_host_3d) STUB(virgl_resource_attach_backing) STUB(virgl_resource_detach_backing) STUB(virgl_cmd_set_scanout) STUB(virgl_cmd_resource_flush) STUB(virgl_cmd_ctx_attach_resource) STUB(virgl_cmd_ctx_detach_resource) STUB(virgl_cmd_get_capset_info) STUB(virtio_gpu_get_display_info) STUB(virtio_gpu_get_edid) STUB(virgl_cmd_resource_create_blob) STUB(virgl_cmd_resource_unmap_blob) STUB(virgl_cmd_set_scanout_blob)
static void virgl_cmd_resource_unref(VirtIOGPU *g,struct virtio_gpu_ctrl_command *c,bool *s){(void)s;dispatch(g,c);}
static void virgl_cmd_resource_map_blob(VirtIOGPU *g,struct virtio_gpu_ctrl_command *c,bool *s){(void)s;dispatch(g,c);}
#define ERRP_GUARD() ((void)0)
#define HOST_BIG_ENDIAN 0
#define TYPE_VIRTIO_GPU_GL "virtio-gpu-gl"
#define VIRTIO_GPU_FLAG_VIRGL_ENABLED 1
#define VIRTIO_GPU_FLAG_CONTEXT_INIT_ENABLED 2
#define virtio_gpu_blob_enabled(c) ((c).blob)
#define virtio_gpu_hostmem_enabled(c) ((c).hostmem>0)
#define virtio_gpu_resource_uuid_enabled(c) ((c).uuid)
#define virtio_gpu_dmabuf_enabled(c) ((c).dmabuf)
static bool display_opengl=true;
static unsigned base_realizes;
static void error_setg(Error **e,const char *s,...){(void)s;*e=(void*)1;}
#define error_append_hint(...) ((void)0)
static void *object_resolve_path_type(const char *p,const char *t,void *a){(void)p;(void)t;(void)a;return (void*)1;}
static void virtio_gpu_device_realize(DeviceState *d,Error **e){(void)d;(void)e;base_realizes++;}
static GArray *g_array_new(bool a,bool b,size_t n){(void)a;(void)b;(void)n;return calloc(1,sizeof(GArray));}
#define g_array_append_val(a,v) ((a)->data[(a)->len++]=(v))
static void virtio_gpu_virgl_add_capset(GArray*,uint32_t);
GArray *virtio_gpu_virgl_get_capsets(VirtIOGPU*);
#include "functions.inc"
static void noop(void *g){(void)g;}
static void setup(VirtIOGPUGL *gl){memset(gl,0,sizeof(*gl));VirtIOGPU *g=&gl->parent_obj;TAILQ_INIT(&g->reslist);TAILQ_INIT(&g->cmdq);TAILQ_INIT(&g->fenceq);TAILQ_INIT(&g->dmabuf.bufs);g->parent_obj.conf.max_outputs=1;g->parent_obj.conf.stats=stats_requested;g->negotiated=true;g->parent_obj.conf.context=true;g->ctrl_bh=new_handle(noop,g);g->reset_bh=new_handle(virtio_gpu_reset_bh,g);gl->ember_classic_lifecycle=true;virtio_gpu_virgl_lifecycle_realize(g);active_g=g;expected_detaches=detaches=unmaps=responses=renderer_calls=dispatches=forced=query_polls=0;premature=oom=inject_fault=inject_display_block=inject_poll=inject_fence=reenter=init_fails=init_oom=false;}
static void teardown(VirtIOGPUGL *gl){virtio_gpu_virgl_lifecycle_unrealize(&gl->parent_obj);qemu_bh_delete(gl->parent_obj.ctrl_bh);qemu_bh_delete(gl->parent_obj.reset_bh);}
static struct virtio_gpu_ctrl_command *command(VirtIOGPU *g,unsigned flags,uint64_t id,uint32_t ctx,bool fence){struct virtio_gpu_ctrl_command *c=calloc(1,sizeof(*c));c->cmd_hdr=(struct virtio_gpu_ctrl_hdr){.type=VIRTIO_GPU_CMD_SUBMIT_3D,.flags=flags,.fence_id=id,.ctx_id=ctx};c->header_valid=true;if(fence){TAILQ_INSERT_TAIL(&g->fenceq,c,next);g->inflight++;}else TAILQ_INSERT_TAIL(&g->cmdq,c,next);return c;}
static void add_resources(VirtIOGPU *g){for(unsigned i=0;i<3;i++){struct virtio_gpu_virgl_resource *r=calloc(1,sizeof(*r));resources[i]=r;r->base.resource_id=i+1;r->base.dmabuf_fd=-1;r->classic_backing_managed=true;r->classic_backing_state=i==2?CLASSIC_BACKING_DETACHED_RETAINED:CLASSIC_BACKING_ATTACHED;r->classic_iov=calloc(1,sizeof(struct iovec));r->classic_iov_count=1;TAILQ_INSERT_TAIL(&g->reslist,&r->base,next);}expected_detaches=2;}
static void reset_cases(void){VirtIOGPUGL gl;setup(&gl);VirtIOGPU *g=&gl.parent_obj;check(virtio_gpu_virgl_init(g)==0,"init");add_resources(g);command(g,1,4,0,true);command(g,0,0,0,false);g->parent_obj.renderer_blocked=1;virtio_gpu_gl_reset(g);check(detaches==2&&unmaps==3&&!premature,"all detach before all release");check(g->reset_finished&&responses==0&&g->inflight==0&&TAILQ_EMPTY(&g->cmdq),"reset drains before finished without response");check(renderer_calls==0&&gl.renderer_live,"blocked reset retains native resources");aio_bh_call(gl.lifecycle_bh);check(gl.classic_state==CL_REVOKED&&renderer_calls==0,"blocked lifecycle does not clean");g->parent_obj.renderer_blocked=0;virtio_gpu_gl_flushed(&g->parent_obj);aio_bh_call(gl.lifecycle_bh);check(gl.classic_state==CL_COLD&&!gl.renderer_live&&TAILQ_EMPTY(&g->reslist),"unblock cleanup before cold");uint64_t old=gl.generation;check(virtio_gpu_virgl_init(g)==0&&gl.generation==old+1,"fresh generation after cleanup");teardown(&gl);}
static void fault_cases(void){VirtIOGPUGL gl;setup(&gl);VirtIOGPU *g=&gl.parent_obj;virtio_gpu_virgl_init(g);add_resources(g);command(g,1,1,0,true);command(g,0,0,0,false);oom=inject_poll=true;virtio_gpu_virgl_fence_poll(g);check(gl.fault_latched&&gl.classic_state==CL_FAULT_PENDING,"actual callback OOM latches without allocation");check(detaches==0&&responses==0,"OOM callback defers barrier");aio_bh_call(gl.lifecycle_bh);check(detaches==2&&unmaps==3&&!premature&&responses==2,"fault responds only after full revoke");check(gl.classic_state==CL_FAULTED&&!gl.renderer_live,"fault terminal after cleanup");teardown(&gl);
for(unsigned fenced=0;fenced<2;fenced++){setup(&gl);g=&gl.parent_obj;virtio_gpu_virgl_init(g);struct virtio_gpu_ctrl_command *c=command(g,fenced,2,0,false);struct iovec iov={&c->cmd_hdr,sizeof(c->cmd_hdr)};c->elem=(VirtQueueElement){&iov,1};command(g,0,0,0,false);inject_fault=true;virtio_gpu_process_cmdq(g);check(dispatches==1&&TAILQ_FIRST(&g->cmdq)==c&&TAILQ_EMPTY(&g->fenceq)&&responses==0,"fault during actual handler retains cmdq owner, no replay");aio_bh_call(gl.lifecycle_bh);check(responses==2&&g->inflight==0,"fault drains both owners once");teardown(&gl);}}
/* A display callback may block admission while the dispatched command owns
 * a response or a newly created fence. The dispatch seam models that boundary;
 * command dispatch, queue handoff and callback delivery remain actual bodies. */
static void display_handoff_cases(void)
{
 for (unsigned flags=0;flags<=3;flags+=flags?2:1) {
  VirtIOGPUGL gl;setup(&gl);VirtIOGPU *g=&gl.parent_obj;virtio_gpu_virgl_init(g);
  struct virtio_gpu_ctrl_command *c=command(g,flags,2,7,false);
  struct iovec v={&c->cmd_hdr,sizeof(c->cmd_hdr)};c->elem=(VirtQueueElement){&v,1};
  inject_display_block=true;virtio_gpu_process_cmdq(g);
  check(TAILQ_EMPTY(&g->cmdq),"display block after dispatch releases cmdq ownership");
  check(flags?(g->inflight==1&&TAILQ_FIRST(&g->fenceq)==c&&responses==0):
              (g->inflight==0&&TAILQ_EMPTY(&g->fenceq)&&responses==1),
        "display block preserves completed response or fence ownership handoff");
  /* Queue a different descriptor: admission must still stop before dispatch. */
  struct virtio_gpu_ctrl_command *next=command(g,0,3,0,false);
  struct iovec nextv={&next->cmd_hdr,sizeof(next->cmd_hdr)};next->elem=(VirtQueueElement){&nextv,1};
  virtio_gpu_process_cmdq(g);
  check(dispatches==1&&next==TAILQ_FIRST(&g->cmdq),
        "display block stops the next command");
  if(flags==1)virgl_write_async_fence(g,2);
  if(flags)aio_bh_call(gl.async_fence_bh);
  check(flags?responses==0:responses==1,"display block defers fence callback response");
  inject_display_block=false;g->parent_obj.renderer_blocked=0;
  virtio_gpu_process_cmdq(g);aio_bh_call(gl.async_fence_bh);
  check(dispatches==2&&TAILQ_EMPTY(&g->cmdq)&&TAILQ_EMPTY(&g->fenceq)&&
        g->inflight==0&&responses==2,"unblock completes each command once without replay");
  teardown(&gl);
 }
}
static void inbox_cases(void){VirtIOGPUGL gl;setup(&gl);VirtIOGPU *g=&gl.parent_obj;virtio_gpu_virgl_init(g);command(g,1,5,0,true);command(g,3,5,1,true);command(g,3,5,2,true);virgl_write_async_context_fence(g,1,0,5);aio_bh_call(gl.async_fence_bh);check(responses==1&&g->inflight==2,"context callback isolated from global and other context");virgl_write_async_fence(g,5);aio_bh_call(gl.async_fence_bh);check(responses==2&&g->inflight==1,"global callback excludes context");virgl_write_async_context_fence(g,2,0,5);SLIST_FIRST(&gl.async_fenceq)->generation--;aio_bh_call(gl.async_fence_bh);check(responses==2&&g->inflight==1,"stale generation cannot complete command");virgl_write_async_context_fence(g,2,0,5);g->parent_obj.renderer_blocked=1;aio_bh_call(gl.async_fence_bh);check(!SLIST_EMPTY(&gl.async_fenceq)&&responses==2,"display block retains success record");g->parent_obj.renderer_blocked=0;virtio_gpu_virgl_cmdq_allowed(g);aio_bh_call(gl.async_fence_bh);check(g->inflight==0&&responses==3,"unblock delivers retained record");teardown(&gl);
setup(&gl);g=&gl.parent_obj;virtio_gpu_virgl_init(g);struct virtio_gpu_ctrl_command *c=command(g,1,9,0,false);struct iovec iov={&c->cmd_hdr,sizeof(c->cmd_hdr)};c->elem=(VirtQueueElement){&iov,1};inject_fence=reenter=true;virtio_gpu_process_cmdq(g);check(g->inflight==1&&responses==0&&gl.async_fence_bh->scheduled,"callback before fenceq handoff preserves wake");aio_bh_call(gl.async_fence_bh);check(g->inflight==0&&responses==1,"callback completes after handoff");teardown(&gl);}
static void init_cases(void){VirtIOGPUGL gl;setup(&gl);VirtIOGPU *g=&gl.parent_obj;unsigned handles=allocated_handles;check(virtio_gpu_virgl_init(g)==0&&init_flags==VIRGL_RENDERER_NATIVE_SHARE_TEXTURE&&!gl.async_fence_enabled,"native-only producer flags");check(gl.fence_poll->scheduled,"empty queues poll starts");gl.fence_poll->scheduled=false;virtio_gpu_virgl_fence_poll(g);check(gl.fence_poll->scheduled&&query_polls==1,"empty queues poll rearms");virtio_gpu_gl_reset(g);aio_bh_call(gl.lifecycle_bh);qemu_egl_display=NULL;check(virtio_gpu_virgl_init(g)==0&&virtio_gpu_3d_cbs.version==3&&virtio_gpu_3d_cbs.get_egl_display==NULL,"callback defaults restored");check(allocated_handles==handles,"repeated init preserves handles");qemu_egl_display=(void*)1;teardown(&gl);
setup(&gl);g=&gl.parent_obj;init_fails=true;init_oom=true;check(virtio_gpu_virgl_init(g)!=0&&gl.classic_state==CL_FAULTED&&!gl.renderer_live&&SLIST_EMPTY(&gl.async_fenceq),"failed init cancels callback records");teardown(&gl);
stats_requested=true;setup(&gl);stats_requested=false;g=&gl.parent_obj;init_oom=true;check(virtio_gpu_virgl_init(g)==0&&gl.renderer_live&&gl.fault_latched&&gl.classic_state==CL_FAULT_PENDING,"successful init preserves callback OOM latch");check(gl.print_stats&&!gl.print_stats->scheduled,"init callback fault does not rearm stats timer");aio_bh_call(gl.lifecycle_bh);check(gl.classic_state==CL_FAULTED&&!gl.renderer_live,"init OOM cleanup");teardown(&gl);
setup(&gl);teardown(&gl);check(allocated_handles==deleted_handles,"never-init and repeated lifecycle free all handles");}
static void policy_cases(void){
 VirtIOGPUGL gl;setup(&gl);VirtIOGPU *g=&gl.parent_obj;Error *e=NULL;
 bool *excluded[]={&g->parent_obj.conf.venus,&g->parent_obj.conf.neptune,&g->parent_obj.conf.blob,&g->parent_obj.conf.uuid,&g->parent_obj.conf.dmabuf};
 for(unsigned i=0;i<5;i++){*excluded[i]=true;virtio_gpu_gl_device_realize(g,&e);check(e&&base_realizes==0&&renderer_calls==0,"profile exclusion before capset advertisement/base realize");*excluded[i]=false;e=NULL;}
 g->parent_obj.conf.hostmem=4096;virtio_gpu_gl_device_realize(g,&e);check(e&&base_realizes==0&&renderer_calls==0,"hostmem exclusion before advertisement");g->parent_obj.conf.hostmem=0;e=NULL;
 virtio_gpu_gl_device_realize(g,&e);check(!e&&base_realizes==1&&g->capset_ids->len==2,"classic capsets only");virtio_gpu_virgl_init(g);
 uint32_t types[]={VIRTIO_GPU_CMD_RESOURCE_CREATE_BLOB,VIRTIO_GPU_CMD_RESOURCE_MAP_BLOB,VIRTIO_GPU_CMD_RESOURCE_UNMAP_BLOB,VIRTIO_GPU_CMD_SET_SCANOUT_BLOB,0xffff};
 for(unsigned i=0;i<5;i++){struct virtio_gpu_ctrl_hdr hdr={.type=types[i]};struct iovec v={&hdr,sizeof(hdr)};struct virtio_gpu_ctrl_command c={.elem={&v,1}};unsigned before=forced;virtio_gpu_virgl_process_cmd(g,&c);check(c.finished&&c.error==VIRTIO_GPU_RESP_ERR_INVALID_PARAMETER&&before==forced,"prohibited command never forces ctx0");}
 for(unsigned i=0;i<2;i++){struct virtio_gpu_ctrl_hdr hdr={.type=VIRTIO_GPU_CMD_SUBMIT_3D,.flags=3,.ring_idx=i?0:1};struct iovec v={&hdr,sizeof(hdr)};struct virtio_gpu_ctrl_command c={.elem={&v,1}};unsigned before=forced;g->negotiated=!i;virtio_gpu_virgl_process_cmd(g,&c);check(c.finished&&c.error&&before==forced,"ring requires negotiation and zero index");}g->negotiated=true;
 struct virtio_gpu_get_capset gc={.capset_id=55};struct iovec v={&gc,sizeof(gc)};struct virtio_gpu_ctrl_command c={.elem={&v,1}};unsigned before=renderer_calls;virgl_cmd_get_capset(g,&c);check(c.error&&renderer_calls==before,"unadvertised capset does not reach renderer");gc.capset_id=VIRTIO_GPU_CAPSET_VIRGL2;c.error=0;virgl_cmd_get_capset(g,&c);check(c.finished&&!c.error&&renderer_calls>before,"advertised VIRGL2 reaches renderer");
 uint32_t flags[]={0x100,VIRTIO_GPU_CAPSET_VIRGL2|0x100,55,VIRTIO_GPU_CAPSET_VIRGL2,0};
 for(unsigned i=0;i<5;i++){struct virtio_gpu_ctx_create cc={.context_init=flags[i]};struct iovec v={&cc,sizeof(cc)};struct virtio_gpu_ctrl_command c={.elem={&v,1}};before=renderer_calls;virgl_cmd_context_create(g,&c);check(i<3?(c.error&&renderer_calls==before):(!c.error&&renderer_calls==before+1),"context init validates bits/id and accepts legacy/VIRGL2");}
 free(g->capset_ids);g->capset_ids=NULL;teardown(&gl);
}
static void ordering_cases(void){
 VirtIOGPUGL gl;setup(&gl);VirtIOGPU *g=&gl.parent_obj;virtio_gpu_virgl_init(g);command(g,1,1,0,true);command(g,0,0,0,false);virgl_write_async_fence(g,1);virtio_gpu_virgl_request_fault(g,NULL,0);virtio_gpu_gl_reset(g);aio_bh_call(gl.async_fence_bh);aio_bh_call(gl.lifecycle_bh);check(!responses&&g->inflight==0&&TAILQ_EMPTY(&g->cmdq)&&TAILQ_EMPTY(&g->fenceq),"fault then reset cancels every response");teardown(&gl);
 setup(&gl);g=&gl.parent_obj;virtio_gpu_virgl_init(g);command(g,1,1,0,true);virgl_write_async_fence(g,1);virtio_gpu_gl_reset(g);virtio_gpu_virgl_request_fault(g,NULL,0);aio_bh_call(gl.async_fence_bh);aio_bh_call(gl.lifecycle_bh);check(!responses&&g->inflight==0&&!gl.fault_latched,"reset then queued fault/success cannot revive owner");teardown(&gl);
 setup(&gl);g=&gl.parent_obj;virtio_gpu_virgl_init(g);virtio_gpu_virgl_request_fault(g,NULL,0);aio_bh_call(gl.lifecycle_bh);unsigned native=renderer_calls,oldpoll=query_polls,oldforce=forced;virtio_gpu_gl_flushed(&g->parent_obj);virtio_gpu_virgl_resume_cmdq_bh(g);virtio_gpu_virgl_fence_poll(g);virtio_gpu_gl_update_cursor_data(g,NULL,1);virtio_gpu_process_cmdq(g);check(native==renderer_calls&&oldpoll==query_polls&&oldforce==forced,"all public producers closed after revoke");
 struct virtio_gpu_ctrl_hdr wire={.flags=3,.fence_id=123,.ctx_id=7};struct iovec v={&wire,sizeof(wire)};struct virtio_gpu_ctrl_command c={.elem={&v,1}};memset(&c.cmd_hdr,0xa5,sizeof(c.cmd_hdr));virtio_gpu_virgl_terminal_response(g,&c);check(c.finished&&c.header_valid&&c.cmd_hdr.fence_id==123&&c.cmd_hdr.ctx_id==7,"terminal response decodes queued wire header");v.iov_len=3;memset(&c,0,sizeof(c));memset(&c.cmd_hdr,0xa5,sizeof(c.cmd_hdr));c.elem=(VirtQueueElement){&v,1};virtio_gpu_virgl_terminal_response(g,&c);check(c.finished&&!c.cmd_hdr.flags&&!c.cmd_hdr.fence_id,"short terminal header never invents fence");teardown(&gl);
}
static void wake_cases(void){
 VirtIOGPUGL gl;setup(&gl);VirtIOGPU *g=&gl.parent_obj;virtio_gpu_virgl_init(g);
 command(g,1,9,0,true);vcpu=true;virtio_gpu_gl_reset(g);vcpu=false;
 check(g->reset_finished&&!g->inflight&&!responses,"actual vCPU reset traverses condition-wait scheduler seam and drains without response");
 struct virtio_gpu_ctrl_hdr wire={.type=VIRTIO_GPU_CMD_SUBMIT_3D};struct iovec v={&wire,sizeof(wire)};
 struct virtio_gpu_ctrl_command *c=calloc(1,sizeof(*c));c->elem=(VirtQueueElement){&v,1};VirtQueue q={.pop=c};
 virtio_gpu_gl_handle_ctrl(g,&q);check(q.pop==c,"control kick during cleanup pending does not pop descriptor");
 aio_bh_call(gl.lifecycle_bh);check(g->ctrl_bh->scheduled&&gl.classic_state==CL_COLD,"cleanup reschedules pending control kick");
 virtio_gpu_gl_handle_ctrl(g,&q);check(!q.pop&&responses==1&&gl.generation==2,"rescheduled control kick initializes and completes request");
 unsigned before=responses;command(g,1,20,0,true);command(g,1,8,0,true);command(g,1,10,0,true);virgl_write_async_fence(g,10);aio_bh_call(gl.async_fence_bh);check(responses==before+2&&g->inflight==1,"out-of-order cumulative global completion accounts per command");
 command(g,3,UINT64_C(1)<<40,7,true);virgl_write_async_context_fence(g,7,0,UINT64_C(1)<<40);aio_bh_call(gl.async_fence_bh);check(g->inflight==1&&responses==before+3,"context completion preserves u64 timeline");
 teardown(&gl);
 setup(&gl);g=&gl.parent_obj;init_oom=true;c=calloc(1,sizeof(*c));c->elem=(VirtQueueElement){&v,1};q.pop=c;
 virtio_gpu_gl_handle_ctrl(g,&q);check(q.pop==c&&!responses&&gl.fault_latched,"init callback OOM retains unread descriptor until revoke");
 g->parent_obj.renderer_blocked=1;aio_bh_call(gl.lifecycle_bh);
 check(g->ctrl_bh->scheduled&&gl.classic_state==CL_REVOKED,"fault revoke reschedules unread init request even while display blocked");
 if(g->ctrl_bh->scheduled)virtio_gpu_gl_handle_ctrl(g,&q);
 check(!q.pop&&responses==1,"terminal fault answers retained init descriptor without another guest kick");
 if(q.pop){free(q.pop);q.pop=NULL;}
 g->parent_obj.renderer_blocked=0;teardown(&gl);
}
static void child_case(int mode){VirtIOGPUGL gl;setup(&gl);VirtIOGPU *g=&gl.parent_obj;virtio_gpu_virgl_init(g);add_resources(g);command(g,1,1,0,true);if(mode==0){resources[2]->mr=(void*)1;invariant_child=true;virtio_gpu_gl_reset(g);}else if(mode==1){block_child=true;g->parent_obj.renderer_blocked=1;virtio_gpu_virgl_lifecycle_unrealize(g);}else if(mode==2){gl.renderer_call_depth=1;invariant_child=true;virtio_gpu_gl_reset(g);}else if(mode==3){ordering_child=true;virtio_gpu_gl_reset(g);}else{mismatch_child=true;virtio_gpu_gl_reset(g);} _exit(0);}
static void invariant_cases(void){for(int i=0;i<4;i++){pid_t p=fork();assert(p>=0);if(!p)child_case(i==3?4:i);int s;waitpid(p,&s,0);check(WIFSIGNALED(s)&&WTERMSIG(s)==SIGABRT,"fail-stop before forbidden cleanup/response/device deletion");}}
int main(void){klass=(VirtIOGPUClass){virtio_gpu_virgl_cmdq_allowed,virtio_gpu_virgl_cmdq_handoff_allowed,virtio_gpu_virgl_reset_resources,virtio_gpu_virgl_process_cmd,virtio_gpu_virgl_resource_destroy};if(getenv("LIFECYCLE_NO_ABI")){VirtIOGPUGL gl;setup(&gl);Error *error=NULL;virtio_gpu_gl_device_realize(&gl.parent_obj,&error);check(error&&base_realizes==0,"old renderer rejects opt-in profile before advertisement");teardown(&gl);puts("old ABI rejected");return fail_count?1:0;}if(getenv("LIFECYCLE_ORDER_CHILD")){pid_t p=fork();assert(p>=0);if(!p)child_case(3);int status;waitpid(p,&status,0);check(WIFEXITED(status)&&WEXITSTATUS(status)==0,"second resource detach precedes any unmap (distinct forbidden-side-effect exit)");return fail_count?1:0;}reset_cases();fault_cases();display_handoff_cases();inbox_cases();init_cases();policy_cases();ordering_cases();wake_cases();invariant_cases();printf("%u checks, %u failures\n",check_count,fail_count);return fail_count?1:0;}

#endif
