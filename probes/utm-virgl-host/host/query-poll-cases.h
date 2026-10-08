/* SPDX-License-Identifier: BSD-2-Clause
 * Origin: EmberBSD, AI-assisted causal query/poll cases. See seam boundaries.
 */
static void fence_callback(void *cookie, uint32_t id) { (void)cookie; (void)id; }
static void context_fence_callback(void *cookie, uint32_t ctx, uint32_t ring, uint64_t id)
{ (void)cookie; (void)ctx; (void)ring; (void)id; }
static void *context_create(void *cookie, int scanout, struct virgl_renderer_gl_ctx_param *params)
{ (void)cookie; (void)scanout; (void)params; return &host_context; }
static void context_destroy(void *cookie, void *ctx) { (void)cookie; (void)ctx; }
static int context_current(void *cookie, int scanout, void *ctx)
{ (void)cookie; (void)scanout; (void)ctx; return 0; }
static struct virgl_renderer_callbacks callbacks = {
    .version = 3, .write_fence = fence_callback,
    .write_context_fence = context_fence_callback, .create_gl_context = context_create,
    .destroy_gl_context = context_destroy, .make_current = context_current
};
static void
retired(uint64_t id, void *data)
{
    (void)data;
    assert(retired_count < 4);
    retired_ids[retired_count++] = id;
}
static void
setup(bool classic)
{
    assert(!state.client_initialized);
    memset(&host_context, 0, sizeof(host_context));
    memset(&guest_context, 0, sizeof(guest_context));
    memset(&host_sub, 0, sizeof(host_sub));
    memset(&guest_sub, 0, sizeof(guest_sub));
    memset(resources, 0, sizeof(resources));
    memset(ready, 0, sizeof(ready));
    memset(retired_ids, 0, sizeof(retired_ids));
    memset(backing, 0xa5, sizeof(backing));
    memset(private_bytes, 0x5a, sizeof(private_bytes));
    native_waits = query_availability = query_results = made_current = 0;
    signaled_fences = retired_count = freed_fences = freed_queries = 0;
    freed_fence_mask = freed_query_mask = 0;
    host_context.sub = &host_sub;
    host_context.fence_retire = retired;
    guest_context.ctx_id = 1;
    guest_context.sub = &guest_sub;
    guest_sub.sub_ctx_id = 1;
    guest_sub.object_hash = objects;
    host_sub.gl_context = &host_sub;
    guest_sub.gl_context = &guest_sub;
    list_inithead(&host_context.sub_ctxs);
    list_inithead(&guest_context.sub_ctxs);
    int ret = classic ? virgl_renderer_ember_classic_init_v1(&state, 0, &callbacks) :
        virgl_renderer_init(&state, 0, &callbacks);
    assert(ret == 0);
}
static void
add_query(unsigned id, bool wide)
{
    assert(id > 0 && id < 4 && !objects[id]);
    struct vrend_query *q = calloc(1, sizeof(*q));
    assert(q);
    q->id = id;
    q->gltype = wide ? GL_TIME_ELAPSED : GL_ANY_SAMPLES_PASSED;
    q->ctx = &guest_context;
    q->sub_ctx_id = 1;
    q->res = &resources[id];
#ifdef QUERY_HAS_BOUNDS
    q->res_handle = 100 + id;
#endif
    list_inithead(&q->waiting_queries);
    objects[id] = q;
    resources[id].base.width0 = sizeof(struct virgl_host_query_state);
    resources[id].ptr = private_bytes[id] + 8;
    resources[id].references = 1;
    vectors[id][0] = (struct iovec){ backing[id] + 8, 5 };
    vectors[id][1] = (struct iovec){ backing[id] + 13, 11 };
    resources[id].iov = vectors[id];
    resources[id].num_iovs = 2;
    int ret = vrend_get_query_result(&guest_context, id, 0);
    assert(ret == 0);
    check(!list_is_empty(&q->waiting_queries) && vrend_state.has_waiting_queries,
        "unready query enters actual pending queue");
}
static void
add_fence(unsigned id)
{
    struct vrend_fence *f = calloc(1, sizeof(*f));
    assert(f);
    f->ctx = &host_context;
    f->fence_id = id;
    f->glsyncobj = (void *)(uintptr_t)id;
    list_addtail(&f->fences, &vrend_state.fence_list);
}
static bool
bytes_equal(const unsigned char *bytes, unsigned char value, size_t size)
{
    for (size_t i = 0; i < size; i++) if (bytes[i] != value) return false;
    return true;
}
static bool
output_matches(unsigned id, bool wide)
{
    unsigned char expected[40];
    memset(expected, 0xa5, sizeof(expected));
    struct virgl_host_query_state value = { .query_state = VIRGL_QUERY_STATE_DONE,
        .result_size = wide ? 8 : 4,
        .result = wide ? UINT64_C(0x123456789abcdef0) : 42 };
    memcpy(expected + 8, &value, sizeof(value));
    return memcmp(backing[id], expected, sizeof(expected)) == 0;
}
static bool
retained_fences_match(unsigned count)
{
    unsigned expected = 1;
    list_for_each_entry(struct vrend_fence, fence, &vrend_state.fence_list, fences) {
        if (expected > count || fence->fence_id != expected ||
            (uintptr_t)fence->glsyncobj != expected) return false;
        expected++;
    }
    return expected == count + 1;
}
static void
cleanup(unsigned queries, unsigned fences)
{
    virgl_renderer_cleanup(&state);
    check(freed_queries == queries && freed_fences == fences,
        "actual cleanup releases queries and every owned fence exactly once");
    check(list_is_empty(&vrend_state.fence_list) && list_is_empty(&vrend_state.waiting_query_list),
        "cleanup leaves no pending query or fence entry");
    for (unsigned id = 1; id < 4; id++)
        check(!objects[id] && !resources[id].references, "query cleanup releases modeled resource reference");
    check(!vrend_state.ember_classic_wait && !vrend_state.ember_wait_failed &&
        virgl_renderer_ember_classic_poll_v1() == -EINVAL,
        "actual cleanup clears profile fault and invalidates checked poll");
}
static void
valid_queries(bool classic, bool fences)
{
    setup(classic);
    add_query(1, false);
    add_query(2, true);
    if (fences) add_fence(1);
    unsigned before = query_availability;
    if (classic) check(virgl_renderer_ember_classic_poll_v1() == 0, "valid pending checked poll succeeds");
    else virgl_renderer_poll();
    check(query_availability == before + 2 && list_length(&vrend_state.waiting_query_list) == 2,
        "pending queries progress even without a retiring fence");
    check(bytes_equal(backing[1], 0xa5, 40) && bytes_equal(backing[2], 0xa5, 40),
        "pending query never writes output");
    ready[2] = true;
    if (classic) check(virgl_renderer_ember_classic_poll_v1() == 0, "one ready query checked poll succeeds");
    else virgl_renderer_poll();
    check(output_matches(2, true) && bytes_equal(backing[1], 0xa5, 40) &&
        list_length(&vrend_state.waiting_query_list) == 1 && vrend_state.has_waiting_queries,
        "64-bit ready query completes while its preceding query stays pending");
    ready[1] = true;
    signaled_fences = 1;
    if (classic) check(virgl_renderer_ember_classic_poll_v1() == 0, "ready query checked poll succeeds");
    else virgl_renderer_poll();
    check(output_matches(1, false) && output_matches(2, true) && query_results == 2 &&
        list_is_empty(&vrend_state.waiting_query_list) && !vrend_state.has_waiting_queries,
        "32-bit and 64-bit results complete once with exact guarded bytes");
    check(retired_count == (unsigned)fences && (!fences || retired_ids[0] == 1),
        "valid poll preserves fence completion");
    cleanup(2, fences ? 1 : 0);
}
static void
legacy_switch_failure(void)
{
    setup(false);
    add_query(1, false);
    guest_context.in_error = true;
    add_fence(1);
    signaled_fences = 1;
    virgl_renderer_poll();
    check(retired_count == 1 && list_is_empty(&vrend_state.waiting_query_list) &&
        !vrend_state.ember_wait_failed, "legacy context switch failure preserves completion policy");
    cleanup(1, 1);
}
static void
failed_query(unsigned reason, bool fences)
{
    setup(true);
    add_query(1, reason == 1);
    if (fences) {
        add_fence(1); add_fence(2); add_fence(3);
        signaled_fences = 2;
    }
    if (reason == 0 || reason == 1) {
        vectors[1][0].iov_len = 4;
        vectors[1][1].iov_len = 4;
    } else if (reason == 2) {
        guest_context.in_error = true;
    } else {
        objects[1]->sub_ctx_id = 77;
    }
    ready[1] = true;
    check(virgl_renderer_ember_classic_poll_v1() == -EIO,
        "delayed query failure reaches checked poll");
    check(!retired_count && retained_fences_match(fences ? 3 : 0),
        "query failure retains signaled fence prefix without success callbacks");
    check(list_is_empty(&vrend_state.waiting_query_list) && !vrend_state.has_waiting_queries,
        "failed query leaves the pending queue");
    check(bytes_equal(backing[1], 0xa5, sizeof(backing[1])) &&
        bytes_equal(private_bytes[1], 0x5a, sizeof(private_bytes[1])),
        "failed query performs no partial output write");
    unsigned waits = native_waits, availability = query_availability, results = query_results;
    check(virgl_renderer_ember_classic_poll_v1() == -EIO &&
        native_waits == waits && query_availability == availability && query_results == results && !retired_count,
        "sticky second poll does no native wait or query work");
    check(virgl_renderer_ember_classic_init_v1(&state, 0, &callbacks) == -EBUSY &&
        virgl_renderer_ember_classic_wait_status_v1() == -EIO,
        "live initialization cannot erase query poll failure");
    cleanup(1, fences ? 3 : 0);
    setup(true);
    check(virgl_renderer_ember_classic_poll_v1() == 0 && !vrend_state.ember_wait_failed,
        "fresh initialization after cleanup clears query poll failure");
    cleanup(0, 0);
}
int
main(void)
{
    /* An accidental queue loop is a failed run, never an unbounded contract. */
    alarm(10);
    valid_queries(true, false);
    valid_queries(true, true);
    valid_queries(false, false);
    valid_queries(false, true);
    legacy_switch_failure();
    printf("query controls: %u checks, %u failures\n", checks, failures);
    for (unsigned reason = 0; reason < 4; reason++) {
        failed_query(reason, false);
        failed_query(reason, true);
    }
    printf("query poll: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
