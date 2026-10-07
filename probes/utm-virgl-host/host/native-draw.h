/*
 * Copyright (C) 2014-2015 Red Hat Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
 * OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 *
 * SPDX-License-Identifier: MIT
 * Origin: tests/testvirgl_encode.c and tests/test_virgl_cmd.c from UTM
 * virglrenderer 5d26f605f50f8e22002ec6db5fb775e1992d4e96.
 * EmberBSD, AI-assisted adaptation: bounded public-API triangle/readback
 * acceptance. The fixed text shader path needs no linked TGSI test helper.
 */
#include <virgl_protocol.h>

static void
draw_submit(uint32_t context, uint32_t *words, size_t count)
{
    if (virgl_renderer_submit_cmd(words, context, (int)count))
        die("VirGL draw command submission");
}

static void
draw_shader(uint32_t context, uint32_t handle, uint32_t type, const char *text)
{
    uint32_t words[128] = {0};
    size_t bytes = strlen(text) + 1;
    size_t payload = VIRGL_OBJ_SHADER_HDR_SIZE(0) + (bytes + 3) / 4;
    if (payload + 1 > sizeof(words) / sizeof(words[0]))
        die("bounded shader command");
    words[0] = VIRGL_CMD0(VIRGL_CCMD_CREATE_OBJECT, VIRGL_OBJECT_SHADER, payload);
    words[VIRGL_OBJ_SHADER_HANDLE] = handle;
    words[VIRGL_OBJ_SHADER_TYPE] = type;
    words[VIRGL_OBJ_SHADER_OFFSET] = VIRGL_OBJ_SHADER_OFFSET_VAL(bytes);
    /* Upstream's text encoder reserves 300 TGSI tokens for a short shader. */
    words[VIRGL_OBJ_SHADER_NUM_TOKENS] = 300;
    memcpy(&words[1 + VIRGL_OBJ_SHADER_HDR_SIZE(0)], text, bytes);
    draw_submit(context, words, payload + 1);
    uint32_t bind[] = {VIRGL_CMD0(VIRGL_CCMD_BIND_SHADER, 0, 2), handle, type};
    draw_submit(context, bind, sizeof(bind) / sizeof(bind[0]));
}

static void
draw_pixels(uint32_t context, uint32_t resource, unsigned char *pixels, int drawn)
{
    struct virgl_box box = {0, 0, 0, 16, 16, 1};
    unsigned inside = 0, outside = 0;
    memset(pixels, 0xa5, 16 * 16 * 4);
    if (virgl_renderer_transfer_read_iov(resource, context, 0, 64, 0,
        &box, 0, NULL, 0) || glGetError() != GL_NO_ERROR)
        die("VirGL triangle readback");
    for (int y = 0; y < 16; y++) {
        for (int x = 0; x < 16; x++) {
            /* Pixel centers and vertices are in doubled framebuffer units.
             * Ignore a narrow edge band; no multisample/edge-rule claim. */
            int px = 2 * x + 1, py = 2 * y + 1;
            int base = py - 4, left = 2 * px - py - 4;
            int right = 60 - 2 * px - py;
            int in = drawn && base > 2 && left > 2 && right > 2;
            int out = !drawn || base < -2 || left < -2 || right < -2;
            if (!in && !out) continue;
            const unsigned char *p = &pixels[(y * 16 + x) * 4];
            if (p[0] != (in ? 255 : 0) || p[1] != (in ? 0 : 255) ||
                p[2] != (in ? 255 : 0) || p[3] != 255) {
                fprintf(stderr, "triangle (%d,%d) inside=%d rgba=%u,%u,%u,%u\n",
                    x, y, in, p[0], p[1], p[2], p[3]);
                die("VirGL triangle pixel oracle");
            }
            inside += in;
            outside += out;
        }
    }
    if (drawn && (inside < 16 || outside < 100))
        die("triangle oracle coverage");
    printf("PASS: native VirGL %s: %u interior and %u background pixels\n",
        drawn ? "shader triangle" : "pre-draw control", inside, outside);
}

static void
check_virgl_draw(struct state *state, unsigned cycle)
{
    const uint32_t context = 8, color = 3, vertex = 2;
    unsigned char pixels[16 * 16 * 4];
    float vertices[][4] = {{-0.75f, -0.75f, 0.0f, 1.0f},
        {0.75f, -0.75f, 0.0f, 1.0f}, {0.0f, 0.75f, 0.0f, 1.0f}};
    struct iovec color_iov = {pixels, sizeof(pixels)};
    struct iovec vertex_iov = {vertices, sizeof(vertices)};
    struct virgl_renderer_resource_create_args texture = {
        .handle = color, .target = PIPE_TEXTURE_2D,
        .format = VIRGL_FORMAT_R8G8B8A8_UNORM,
        .bind = VIRGL_BIND_RENDER_TARGET | VIRGL_BIND_SAMPLER_VIEW,
        .width = 16, .height = 16, .depth = 1, .array_size = 1
    };
    struct virgl_renderer_resource_create_args buffer = {
        .handle = vertex, .target = PIPE_BUFFER, .format = VIRGL_FORMAT_R8_UNORM,
        .bind = VIRGL_BIND_VERTEX_BUFFER, .width = sizeof(vertices),
        .height = 1, .depth = 1, .array_size = 1
    };
    struct virgl_box vertex_box = {0, 0, 0, sizeof(vertices), 1, 1};
    if (virgl_renderer_resource_create(&texture, NULL, 0) ||
        virgl_renderer_resource_create(&buffer, NULL, 0) ||
        virgl_renderer_resource_attach_iov(color, &color_iov, 1) ||
        virgl_renderer_resource_attach_iov(vertex, &vertex_iov, 1) ||
        virgl_renderer_context_create(context, 4, "draw"))
        die("triangle resource/context creation");
    virgl_renderer_ctx_attach_resource(context, color);
    virgl_renderer_ctx_attach_resource(context, vertex);
    if (virgl_renderer_transfer_write_iov(vertex, context, 0, 0, 0,
        &vertex_box, 0, NULL, 0)) die("triangle vertex upload");
    uint32_t setup[] = {
        VIRGL_CMD0(VIRGL_CCMD_CREATE_OBJECT, VIRGL_OBJECT_SURFACE, VIRGL_OBJ_SURFACE_SIZE),
        1, color, VIRGL_FORMAT_R8G8B8A8_UNORM, 0, 0,
        VIRGL_CMD0(VIRGL_CCMD_SET_FRAMEBUFFER_STATE, 0, VIRGL_SET_FRAMEBUFFER_STATE_SIZE(1)),
        1, 0, 1,
        VIRGL_CMD0(VIRGL_CCMD_CLEAR, 0, VIRGL_OBJ_CLEAR_SIZE),
        PIPE_CLEAR_COLOR0, 0, UINT32_C(0x3f800000), 0, UINT32_C(0x3f800000), 0, 0, 0,
        VIRGL_CMD0(VIRGL_CCMD_CREATE_OBJECT, VIRGL_OBJECT_VERTEX_ELEMENTS, VIRGL_OBJ_VERTEX_ELEMENTS_SIZE(1)),
        2, 0, 0, 0, VIRGL_FORMAT_R32G32B32A32_FLOAT,
        VIRGL_CMD0(VIRGL_CCMD_BIND_OBJECT, VIRGL_OBJECT_VERTEX_ELEMENTS, 1), 2,
        VIRGL_CMD0(VIRGL_CCMD_SET_VERTEX_BUFFERS, 0, VIRGL_SET_VERTEX_BUFFERS_SIZE(1)),
        sizeof(vertices[0]), 0, vertex,
        VIRGL_CMD0(VIRGL_CCMD_CREATE_OBJECT, VIRGL_OBJECT_BLEND, VIRGL_OBJ_BLEND_SIZE),
        5, 0, 0, VIRGL_OBJ_BLEND_S2_RT_COLORMASK(15), 0, 0, 0, 0, 0, 0, 0,
        VIRGL_CMD0(VIRGL_CCMD_BIND_OBJECT, VIRGL_OBJECT_BLEND, 1), 5,
        VIRGL_CMD0(VIRGL_CCMD_CREATE_OBJECT, VIRGL_OBJECT_DSA, VIRGL_OBJ_DSA_SIZE),
        6, 0, 0, 0, 0,
        VIRGL_CMD0(VIRGL_CCMD_BIND_OBJECT, VIRGL_OBJECT_DSA, 1), 6,
        VIRGL_CMD0(VIRGL_CCMD_CREATE_OBJECT, VIRGL_OBJECT_RASTERIZER, VIRGL_OBJ_RS_SIZE),
        7, VIRGL_OBJ_RS_S0_DEPTH_CLIP(1) | VIRGL_OBJ_RS_S0_HALF_PIXEL_CENTER(1) |
            VIRGL_OBJ_RS_S0_BOTTOM_EDGE_RULE(1),
        UINT32_C(0x3f800000), 0, 0, UINT32_C(0x3f800000), 0, 0, 0,
        VIRGL_CMD0(VIRGL_CCMD_BIND_OBJECT, VIRGL_OBJECT_RASTERIZER, 1), 7,
        VIRGL_CMD0(VIRGL_CCMD_SET_VIEWPORT_STATE, 0, VIRGL_SET_VIEWPORT_STATE_SIZE(1)),
        0, UINT32_C(0x41000000), UINT32_C(0x41000000), UINT32_C(0x3f000000),
        UINT32_C(0x41000000), UINT32_C(0x41000000), UINT32_C(0x3f000000)
    };
    draw_submit(context, setup, sizeof(setup) / sizeof(setup[0]));
    draw_shader(context, 3, PIPE_SHADER_VERTEX,
        "VERT\nDCL IN[0]\nDCL OUT[0], POSITION\n0: MOV OUT[0], IN[0]\n1: END\n");
    draw_shader(context, 4, PIPE_SHADER_FRAGMENT,
        "FRAG\nDCL OUT[0], COLOR\nIMM[0] FLT32 {1.0, 0.0, 1.0, 1.0}\n"
        "0: MOV OUT[0], IMM[0]\n1: END\n");
    uint32_t link[] = {VIRGL_CMD0(VIRGL_CCMD_LINK_SHADER, 0, VIRGL_LINK_SHADER_SIZE),
        3, 4, 0, 0, 0, 0};
    draw_submit(context, link, sizeof(link) / sizeof(link[0]));
    draw_pixels(context, color, pixels, 0);
    uint32_t draw[] = {VIRGL_CMD0(VIRGL_CCMD_DRAW_VBO, 0, VIRGL_DRAW_VBO_SIZE),
        0, 3, PIPE_PRIM_TRIANGLES, 0, 1, 0, 0, 0, 0, 0, 2, 0};
    draw_submit(context, draw, sizeof(draw) / sizeof(draw[0]));
    /* The legacy fence API tags ctx0 but inserts GL sync in the current draw
     * context. Wait before changing context or destroying any draw resource. */
    const uint32_t fence = 500 + cycle;
    state->fence = 0;
    if (virgl_renderer_create_fence((int)fence, context)) die("triangle fence");
    for (unsigned poll = 0; state->fence != fence && poll < 2000; poll++) {
        if (virgl_renderer_ember_classic_poll_v1()) die("triangle fence poll");
        if (state->fence != fence) usleep(1000);
    }
    if (state->fence != fence) die("triangle fence deadline");
    draw_pixels(context, color, pixels, 1);
    virgl_renderer_ctx_detach_resource(context, vertex);
    virgl_renderer_ctx_detach_resource(context, color);
    virgl_renderer_context_destroy(context);
    struct iovec *detached = NULL;
    int count = 0;
    virgl_renderer_resource_detach_iov(vertex, &detached, &count);
    if (detached != &vertex_iov || count != 1) die("vertex backing ownership");
    virgl_renderer_resource_unref(vertex);
    virgl_renderer_resource_detach_iov(color, &detached, &count);
    if (detached != &color_iov || count != 1) die("triangle backing ownership");
    virgl_renderer_resource_unref(color);
}
