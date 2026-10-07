/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD, AI-assisted full-renderer context/GL error regression. */
static void
check_context_errors(int classic)
{
    struct context_case {
        const char *name;
        uint32_t words[4];
        int count;
    } cases[] = {
        {"unknown color surface", {
            VIRGL_CMD0(VIRGL_CCMD_SET_FRAMEBUFFER_STATE, 0,
                VIRGL_SET_FRAMEBUFFER_STATE_SIZE(1)), 1, 0, 42}, 4},
        {"unknown depth surface", {
            VIRGL_CMD0(VIRGL_CCMD_SET_FRAMEBUFFER_STATE, 0,
                VIRGL_SET_FRAMEBUFFER_STATE_SIZE(0)), 0, 42}, 3},
        {"injected GL_INVALID_ENUM", {VIRGL_CCMD_NOP}, 1},
    };
    uint32_t nop = VIRGL_CCMD_NOP;
    unsigned failures = 0, checks = 0;
    for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        const uint32_t id = 170 + i;
        if (virgl_renderer_context_create(id, 6, "errors") ||
            virgl_renderer_submit_cmd(&nop, id, 1))
            die("healthy error-test context");
        if (glGetError() != GL_NO_ERROR) die("unexpected pre-test GL error");
        /* The context is current. Inject a real GL error, without draining it. */
        if (i == 2) glEnable((GLenum)UINT32_MAX);
        int results[3];
        results[0] = virgl_renderer_submit_cmd(cases[i].words, id, cases[i].count);
        results[1] = virgl_renderer_submit_cmd(&nop, id, 0);
        results[2] = virgl_renderer_submit_cmd(&nop, id, 1);
        for (unsigned j = 0; j < sizeof(results) / sizeof(results[0]); j++) {
            int expected = classic ? EINVAL : 0;
#ifdef CHECK_GL_ERRORS
            /* Legacy debug builds reject the first GL error, then forget it. */
            if (!classic && i == 2 && j == 0) expected = EINVAL;
#endif
            printf("context-error %s %s step=%u: result=%d expected=%d\n",
                classic ? "classic" : "legacy", cases[i].name, j,
                results[j], expected);
            checks++;
            if (results[j] != expected) failures++;
        }
        virgl_renderer_context_destroy(id);
        /* A rejected context must not poison a new, independent context. */
        if (virgl_renderer_context_create(id, 6, "errors"))
            die("recreated error-test context");
        int result = virgl_renderer_submit_cmd(&nop, id, 1);
        checks++;
        if (result) failures++;
        virgl_renderer_context_destroy(id);
    }
    printf("context-errors %s: %u checks, %u failures\n",
        classic ? "classic" : "legacy", checks, failures);
    if (failures) die("context/GL error returned incorrect command result");
}
