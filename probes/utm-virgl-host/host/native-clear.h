/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD, AI-assisted native classic command/readback probe. */
static void
check_virgl_clear(unsigned char *backing, size_t size, unsigned cycle)
{
    /* One surface, one color attachment, then red/green alternating clears. */
    const uint32_t channel = (cycle & 1) ? UINT32_C(0x3f800000) : 0;
    uint32_t commands[] = {
        VIRGL_CMD0(VIRGL_CCMD_CREATE_OBJECT, VIRGL_OBJECT_SURFACE,
            VIRGL_OBJ_SURFACE_SIZE),
        1, 1, VIRGL_FORMAT_R8G8B8A8_UNORM, 0, 0,
        VIRGL_CMD0(VIRGL_CCMD_SET_FRAMEBUFFER_STATE, 0,
            VIRGL_SET_FRAMEBUFFER_STATE_SIZE(1)), 1, 0, 1,
        VIRGL_CMD0(VIRGL_CCMD_CLEAR, 0, VIRGL_OBJ_CLEAR_SIZE),
        PIPE_CLEAR_COLOR0, channel, channel ^ UINT32_C(0x3f800000),
        0, UINT32_C(0x3f800000), 0, 0, 0
    };
    const uint32_t context = 7;
    struct virgl_box box = {0, 0, 0, 16, 16, 1};
    if (virgl_renderer_context_create(context, 5, "clear"))
        die("clear context creation");
    virgl_renderer_ctx_attach_resource(context, 1);
    if (virgl_renderer_submit_cmd(commands, context,
        sizeof(commands) / sizeof(commands[0]))) die("VirGL clear command");
    memset(backing, 0xa5, size);
    if (virgl_renderer_transfer_read_iov(1, context, 0, 64, 0,
        &box, 0, NULL, 0)) die("VirGL clear readback");
    if (glGetError() != GL_NO_ERROR) die("VirGL clear GL error");
    for (size_t i = 0; i < size; i += 4) {
        if (backing[i] != ((cycle & 1) ? 255 : 0) ||
            backing[i + 1] != ((cycle & 1) ? 0 : 255) ||
            backing[i + 2] != 0 || backing[i + 3] != 255)
            die("VirGL clear pixel mismatch");
    }
    virgl_renderer_ctx_detach_resource(context, 1);
    virgl_renderer_context_destroy(context);
    puts("PASS: native VirGL surface/framebuffer/clear, 256 exact pixels");
}
