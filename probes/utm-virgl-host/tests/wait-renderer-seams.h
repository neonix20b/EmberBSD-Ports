/* SPDX-License-Identifier: BSD-2-Clause
 * Native GL/EGL/poll and backend-lifetime seams. Production wait, list,
 * retirement, profile-init, poll API and cleanup bodies are extracted whole.
 */
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <poll.h>
#include <unistd.h>
#ifdef NDEBUG
#undef assert
#define assert(x) ((x)?(void)0:abort())
#endif
#include "virglrenderer.h"
#ifdef LIST_ENTRY
#undef LIST_ENTRY
#endif
#include "wait-list.h"
#define HAVE_EPOXY_EGL_H 1
#define TRACE_FUNC() ((void)0)
#define UNUSED __attribute__((unused))
#define virgl_warn(...) ((void)0)
#define virgl_error(...) ((void)0)
#define GL_TIMEOUT_EXPIRED 0x911b
#define GL_WAIT_FAILED 0x911d
#define GL_ALREADY_SIGNALED 0x911a
#define GL_CONDITION_SATISFIED 0x911c
#define EGL_FALSE 0
#define EGL_CONDITION_SATISFIED_KHR 0x30f6
#define EGL_TIMEOUT_EXPIRED_KHR 0x30f5
#define EGL_FOREVER_KHR UINT64_MAX
typedef unsigned GLenum;
typedef void *GLsync;
typedef int EGLint;
typedef void *EGLSyncKHR;
typedef float GLfloat;
typedef int mtx_t;typedef int thrd_t;typedef int cnd_t;
typedef void *virgl_gl_context;
enum {feat_last=0};
struct vrend_context {int ctx_id;void(*fence_retire)(uint64_t,void*);void *fence_retire_data;};
#include "wait-fence.inc"
#include "wait-state.inc"
static struct global_renderer_state vrend_state;
struct virgl_egl {void *egl_display;};
static struct virgl_egl egl_object,*egl=&egl_object;
static unsigned native_results[8],native_count,native_at,native_calls,poll_calls,close_calls,query_calls,retired_count,freed_fences;
static int poll_result,poll_errno;
static short poll_events;
static bool use_fd,poll_retry_once;
static unsigned next_native(void){native_calls++;assert(native_at<native_count);return native_results[native_at++];}
static GLenum glClientWaitSync(GLsync f,unsigned flags,uint64_t timeout){(void)f;assert(!flags && timeout<=1000000000);return next_native();}
static EGLint eglClientWaitSyncKHR(void *d,EGLSyncKHR f,unsigned flags,uint64_t timeout){(void)d;(void)f;assert(!flags && (timeout==0 || timeout==EGL_FOREVER_KHR));return next_native();}
static bool virgl_egl_export_fence(struct virgl_egl *e,EGLSyncKHR f,int *fd){(void)e;(void)f;*fd=use_fd?10:-1;return use_fd;}
static int wait_poll(struct pollfd *p,nfds_t n,int timeout){assert(n==1 && p->fd==10 && p->events==POLLIN && (timeout==0 || timeout==-1));poll_calls++;if(poll_retry_once && poll_calls==1){errno=EINTR;return -1;}p->revents=poll_events;errno=poll_errno;return poll_result;}
static int wait_close(int fd){assert(fd==10);close_calls++;errno=EBADF;return 0;}
#define poll wait_poll
#define close wait_close
#include "wait-egl.inc"
#undef poll
#undef close
static void glDeleteSync(GLsync f){(void)f;freed_fences++;}
static void virgl_egl_fence_destroy(struct virgl_egl *e,EGLSyncKHR f){(void)e;(void)f;freed_fences++;}
static void vrend_renderer_force_ctx_0(void){}
static void vrend_renderer_check_queries(void){query_calls++;}
static void flush_eventfd(int fd){(void)fd;abort();}
static void mtx_lock(mtx_t *m){(void)m;abort();}
static void mtx_unlock(mtx_t *m){(void)m;abort();}
static void cnd_signal(cnd_t *c){(void)c;abort();}
static void vrend_blitter_fini(void){}
static void vrend_destroy_context(struct vrend_context *c){(void)c;
#ifdef WAIT_QEMU
 cleanup_calls++;native_live=false;
#endif
}
#include "wait-renderer.inc"
#ifndef WAIT_QEMU
#include "wait-api-state.inc"
static struct global_state state;
int virgl_renderer_init(void *p,int flags,struct virgl_renderer_callbacks *c){state.client_initialized=state.vrend_initialized=true;state.cookie=p;state.flags=flags;state.cbs=c;return 0;}
struct virgl_context {void(*retire_fences)(struct virgl_context*);};
static struct virgl_context context_poll_object;
static struct virgl_context *virgl_context_lookup(unsigned id){return id==7?&context_poll_object:NULL;}
#include "wait-context.inc"
#else
int virgl_renderer_init(void *p,int flags,struct virgl_renderer_callbacks *c)
{
 assert(!native_live);init_calls++;init_flags=flags;native_live=true;
 state.client_initialized=state.vrend_initialized=true;
 state.cookie=p;state.flags=flags;state.cbs=c;
 list_inithead(&vrend_state.fence_list);list_inithead(&vrend_state.fence_wait_list);
 vrend_state.eventfd=-1;return 0;
}
#endif
struct virgl_context_foreach_args {bool(*callback)(struct virgl_context*,void*);};
static bool virgl_context_foreach_retire_fences(struct virgl_context *c,void *p){(void)c;(void)p;return true;}
static void virgl_context_foreach(struct virgl_context_foreach_args *a){(void)a;}
static void vrend_renderer_prepare_reset(void){}
static void virgl_context_table_cleanup(void){}
static void virgl_resource_table_cleanup(void){}
static void proxy_renderer_fini(void){}
static void virgl_fence_table_cleanup(void){}
static void vrend_winsys_cleanup(void){}
static void drm_renderer_fini(void){}
static void vkr_allocator_fini(void){}
#include "wait-api.inc"
