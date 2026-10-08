/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD, AI-assisted full-renderer query output/lifetime regression. */
static void
check_query_outputs(void)
{
    const char *names[] = {"split IOV", "private storage", "short resource",
        "short IOV", "short replacement", "detached IOV", "unreferenced IOV"};
    unsigned checks = 0, failures = 0;
    for (unsigned mode = 0; mode < sizeof(names) / sizeof(names[0]); mode++) {
        const uint32_t context = 205 + mode, resource = 301 + mode;
        unsigned char backing[32], replacement[32], expected[32];
        memset(backing, 0xa5, sizeof(backing));
        memset(replacement, 0x5a, sizeof(replacement));
        struct iovec iov[2] = {{backing + 4, 5}, {backing + 9, 11}};
        struct iovec short_iov = {replacement + 4, 8};
        struct virgl_renderer_resource_create_args args = {
            .handle = resource, .target = PIPE_BUFFER,
            .format = VIRGL_FORMAT_R8_UNORM, .bind = VIRGL_BIND_CUSTOM,
            .width = mode == 2 ? 8 : 16, .height = 1, .depth = 1,
            .array_size = 1
        };
        if (virgl_renderer_context_create(context, 5, "query") ||
            virgl_renderer_resource_create(&args, NULL, 0)) die("query setup");
        virgl_renderer_ctx_attach_resource(context, resource);
        if (mode != 1 && virgl_renderer_resource_attach_iov(resource,
            mode == 3 ? &short_iov : iov, mode == 3 ? 1 : 2))
            die("query backing attach");
        /* Attachment copies private storage; isolate command writes from it. */
        memset(backing, 0xa5, sizeof(backing));
        memset(replacement, 0x5a, sizeof(replacement));
        uint32_t create[] = {VIRGL_CMD0(VIRGL_CCMD_CREATE_OBJECT,
            VIRGL_OBJECT_QUERY, VIRGL_OBJ_QUERY_SIZE), 9,
            PIPE_QUERY_OCCLUSION_PREDICATE, 0, resource};
        int result = virgl_renderer_submit_cmd(create, context, 5);
        if (mode == 2 || mode == 3) {
            checks++;
            if (result != EINVAL) failures++;
            printf("query %s create: result=%d expected=%d\n",
                names[mode], result, EINVAL);
        } else {
            if (result) die("valid query creation");
            uint32_t commands[] = {
                VIRGL_CMD0(VIRGL_CCMD_BEGIN_QUERY, 0, 1), 9,
                VIRGL_CMD0(VIRGL_CCMD_END_QUERY, 0, 1), 9
            };
            if (virgl_renderer_submit_cmd(commands, context, 4))
                die("query begin/end");
            glFinish();
            if (glGetError() != GL_NO_ERROR) die("query GL completion");
            if (mode == 4 || mode == 5) {
                struct iovec *detached = NULL;
                int count = 0;
                virgl_renderer_resource_detach_iov(resource, &detached, &count);
                if (detached != iov || count != 2) die("query exact IOV detach");
                if (mode == 4 && virgl_renderer_resource_attach_iov(resource,
                    &short_iov, 1)) die("short replacement attach");
            }
            if (mode == 6) virgl_renderer_resource_unref(resource);
            memset(backing, 0xa5, sizeof(backing));
            memset(replacement, 0x5a, sizeof(replacement));
            uint32_t get[] = {VIRGL_CMD0(VIRGL_CCMD_GET_QUERY_RESULT, 0, 2), 9, 0};
            result = virgl_renderer_submit_cmd(get, context, 3);
            checks++;
            if (result != (mode == 4 ? EINVAL : 0)) failures++;
            if (mode == 1 || mode == 5) {
                if (virgl_renderer_resource_attach_iov(resource, iov, 2))
                    die("query private result attachment");
            }
            struct virgl_host_query_state state = {
                .query_state = VIRGL_QUERY_STATE_DONE, .result_size = 4,
                .result = 0
            };
            memset(expected, 0xa5, sizeof(expected));
            if (mode == 0 || mode == 1 || mode == 5)
                memcpy(expected + 4, &state, sizeof(state));
            checks++;
            if (memcmp(backing, expected, sizeof(backing))) failures++;
            memset(expected, 0x5a, sizeof(expected));
            checks++;
            if (memcmp(replacement, expected, sizeof(replacement))) failures++;
            printf("query %s: result=%d, cumulative failures=%u\n",
                names[mode], result, failures);
        }
        virgl_renderer_context_destroy(context);
        if (mode != 6) {
            virgl_renderer_resource_detach_iov(resource, NULL, NULL);
            virgl_renderer_resource_unref(resource);
        }
    }
    printf("query outputs: %u checks, %u failures\n", checks, failures);
    if (failures) die("query output bounds/lifetime");
}
