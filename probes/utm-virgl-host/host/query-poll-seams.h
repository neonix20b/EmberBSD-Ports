/* SPDX-License-Identifier: BSD-2-Clause
 * Origin: EmberBSD, AI-assisted deterministic query/poll software model.
 * GL availability/results and fence signals are controlled embedding seams.
 * Production query, context switching, list, fence retirement, checked poll,
 * profile initialization, fini and public cleanup bodies are extracted whole.
 * Complete source copies retain their Red Hat MIT and IOV BSD notices.
 * Context/object setup and resource refcounts model embedding ownership; this
 * does not test command decoding, real GL, thread synchronization or VM reset.
 */
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/uio.h>
#include <unistd.h>
#include "virglrenderer.h"
#include "virgl_hw.h"
#include "virgl_protocol.h"
#ifdef LIST_ENTRY
#undef LIST_ENTRY
#endif
#include "query-list.h"
#define TRACE_FUNC() ((void)0)
#define UNUSED __attribute__((unused))
#define virgl_warn(...) ((void)0)
#define virgl_error(...) ((void)0)
#define GL_TIMEOUT_EXPIRED 0x911b
#define GL_WAIT_FAILED 0x911d
#define GL_ALREADY_SIGNALED 0x911a
#define GL_CONDITION_SATISFIED 0x911c
#define GL_QUERY_RESULT_AVAILABLE_ARB 0x8867
#define GL_QUERY_RESULT_ARB 0x8866
#define GL_TIMESTAMP 0x8e28
#define GL_TIME_ELAPSED 0x88bf
#define GL_ANY_SAMPLES_PASSED 0x8c2f
typedef unsigned GLenum;
typedef unsigned GLuint;
typedef uint64_t GLuint64;
typedef void *GLsync;
typedef float GLfloat;
typedef int mtx_t;
typedef int thrd_t;
typedef int cnd_t;
typedef void *virgl_gl_context;
enum { feat_last = 0 };
static const uint32_t fake_occlusion_query_samples_passed_default = 1024;
struct vrend_sub_context {
    int sub_ctx_id;
    struct list_head head;
    unsigned fake_occlusion_query_samples_passed_multiplier;
    void *object_hash, *gl_context;
};
struct vrend_context {
    int ctx_id;
    bool in_error, ctx_switch_pending;
    enum virgl_ctx_errors last_error;
    struct vrend_sub_context *sub;
    struct list_head sub_ctxs;
    void (*fence_retire)(uint64_t, void *);
    void *fence_retire_data;
};
struct vrend_resource {
    struct { uint32_t width0; } base;
    const struct iovec *iov;
    uint32_t num_iovs;
    void *ptr;
    unsigned references;
};
#include "query-fence.inc"
#include "query-shape.inc"
#include "query-state.inc"
#include "query-api-state.inc"
static struct global_renderer_state vrend_state;
static struct global_state state;
static struct vrend_context host_context, guest_context;
static struct vrend_sub_context host_sub, guest_sub;
static struct vrend_query *objects[4];
static struct vrend_resource resources[4];
static unsigned char backing[4][40];
static _Alignas(8) unsigned char private_bytes[4][32];
static struct iovec vectors[4][2];
static bool ready[4];
static unsigned signaled_fences, native_waits, query_availability, query_results;
static unsigned retired_count, freed_fences, freed_queries, made_current;
static unsigned freed_fence_mask, freed_query_mask;
static uint64_t retired_ids[4];
static unsigned checks, failures;
#include "prototypes.inc"
static void
check(bool condition, const char *message)
{
    checks++;
    if (!condition) {
        failures++;
        fprintf(stderr, "FAIL %s\n", message);
    }
}
static GLenum
glClientWaitSync(GLsync sync, unsigned flags, uint64_t timeout)
{
    assert(!flags && timeout == 0);
    native_waits++;
    return (uintptr_t)sync <= signaled_fences ? GL_ALREADY_SIGNALED : GL_TIMEOUT_EXPIRED;
}
static void
glDeleteSync(GLsync sync)
{
    unsigned id = (unsigned)(uintptr_t)sync;
    assert(id > 0 && id < 4 && !(freed_fence_mask & (1u << id)));
    freed_fence_mask |= 1u << id;
    freed_fences++;
}
static void
glGetQueryObjectuiv(GLuint id, GLenum name, GLuint *value)
{
    assert(id > 0 && id < 4);
    if (name == GL_QUERY_RESULT_AVAILABLE_ARB) {
        query_availability++;
        *value = ready[id];
    } else {
        assert(name == GL_QUERY_RESULT_ARB && ready[id]);
        query_results++;
        *value = 42;
    }
}
static void
glGetQueryObjectui64v(GLuint id, GLenum name, GLuint64 *value)
{
    assert(id > 0 && id < 4 && name == GL_QUERY_RESULT_ARB && ready[id]);
    query_results++;
    *value = UINT64_C(0x123456789abcdef0);
}
static void
glDeleteQueries(int count, const GLuint *id)
{
    assert(count == 1 && *id > 0 && *id < 4 && !(freed_query_mask & (1u << *id)));
    freed_query_mask |= 1u << *id;
    freed_queries++;
}
static void *vrend_get_context_tweaks(struct vrend_context *ctx) { return ctx; }
static bool
vrend_get_tweak_is_active_with_params(void *tweaks, unsigned tweak, uint32_t *value)
{
    (void)tweaks; (void)tweak; (void)value;
    return false;
}
#define vrend_report_context_error(ctx, error, value) \
    vrend_report_context_error_internal(__func__, ctx, error, value)
static void *
vrend_object_lookup(void *table, unsigned handle, unsigned type)
{
    assert(table == objects && type == VIRGL_OBJECT_QUERY);
    return handle < 4 ? objects[handle] : NULL;
}
static void
vrend_resource_reference(struct vrend_resource **dst, struct vrend_resource *src)
{
    assert(!src && *dst && (*dst)->references == 1);
    (*dst)->references--;
    *dst = NULL;
}
static void make_current(void *context) { assert(context); made_current++; }
static const struct { void (*make_current)(void *); } native_callbacks = { make_current };
static const __typeof__(native_callbacks) *vrend_clicbs = &native_callbacks;
static void flush_eventfd(int fd) { (void)fd; abort(); }
static void mtx_lock(mtx_t *m) { (void)m; abort(); }
static void mtx_unlock(mtx_t *m) { (void)m; abort(); }
static void cnd_signal(cnd_t *c) { (void)c; abort(); }
static void vrend_blitter_fini(void) {}
static void vrend_destroy_context(struct vrend_context *ctx) { assert(ctx == &host_context); }
struct virgl_context {};
struct virgl_context_foreach_args { bool (*callback)(struct virgl_context *, void *); };
static bool virgl_context_foreach_retire_fences(struct virgl_context *ctx, void *data)
{ (void)ctx; (void)data; return true; }
static void virgl_context_foreach(struct virgl_context_foreach_args *args) { (void)args; }
static void vrend_renderer_prepare_reset(void) { assert(!vrend_state.sync_thread); }
static void
virgl_context_table_cleanup(void)
{
    for (unsigned id = 1; id < 4; id++) {
        if (objects[id]) {
            vrend_destroy_query(objects[id]);
            objects[id] = NULL;
        }
    }
}
static void virgl_resource_table_cleanup(void) {}
static void proxy_renderer_fini(void) { abort(); }
static void virgl_fence_table_cleanup(void) {}
static void vrend_winsys_cleanup(void) {}
static void drm_renderer_fini(void) { abort(); }
static void vkr_allocator_fini(void) {}
int
virgl_renderer_init(void *cookie, int flags, struct virgl_renderer_callbacks *cbs)
{
    assert(!state.client_initialized);
    state.client_initialized = state.vrend_initialized = state.context_initialized = true;
    state.cookie = cookie;
    state.flags = flags;
    state.cbs = cbs;
    list_inithead(&vrend_state.fence_list);
    list_inithead(&vrend_state.fence_wait_list);
    list_inithead(&vrend_state.waiting_query_list);
    atomic_store(&vrend_state.has_waiting_queries, false);
    vrend_state.ctx0 = &host_context;
    vrend_state.eventfd = -1;
    return 0;
}
