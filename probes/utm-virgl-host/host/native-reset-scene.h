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
 * setup reused for a real reset with live objects and attached caller IOVs.
 */
struct reset_scene {
    unsigned char leading[32];
    unsigned char pixels[16 * 16 * 4];
    float vertices[3][4];
    unsigned char trailing[32];
    struct iovec color_iov, vertex_iov;
};

/* Leave every renderer object and both caller IOVs live. No poll or readback
 * follows DRAW_VBO; the caller immediately creates its unreported fence. */
static void
reset_scene_submit(struct reset_scene *scene)
{
    const uint32_t context = 8, color = 3, vertex = 2;
    const float triangle[3][4] = {{-0.75f, -0.75f, 0.0f, 1.0f},
        {0.75f, -0.75f, 0.0f, 1.0f}, {0.0f, 0.75f, 0.0f, 1.0f}};
    memset(scene, 0xa5, sizeof(*scene));
    memcpy(scene->vertices, triangle, sizeof(triangle));
    scene->color_iov = (struct iovec){scene->pixels, sizeof(scene->pixels)};
    scene->vertex_iov = (struct iovec){scene->vertices, sizeof(scene->vertices)};
    unsigned char *pixels = scene->pixels;
    float (*vertices)[4] = scene->vertices;
    struct virgl_renderer_resource_create_args texture = {
        .handle = color, .target = PIPE_TEXTURE_2D,
        .format = VIRGL_FORMAT_R8G8B8A8_UNORM,
        .bind = VIRGL_BIND_RENDER_TARGET | VIRGL_BIND_SAMPLER_VIEW,
        .width = 16, .height = 16, .depth = 1, .array_size = 1
    };
    struct virgl_renderer_resource_create_args buffer = {
        .handle = vertex, .target = PIPE_BUFFER, .format = VIRGL_FORMAT_R8_UNORM,
        .bind = VIRGL_BIND_VERTEX_BUFFER, .width = sizeof(scene->vertices),
        .height = 1, .depth = 1, .array_size = 1
    };
    struct virgl_box vertex_box = {0, 0, 0, sizeof(scene->vertices), 1, 1};
    if (virgl_renderer_resource_create(&texture, NULL, 0) ||
        virgl_renderer_resource_create(&buffer, NULL, 0) ||
        virgl_renderer_resource_attach_iov(color, &scene->color_iov, 1) ||
        virgl_renderer_resource_attach_iov(vertex, &scene->vertex_iov, 1) ||
        virgl_renderer_context_create(context, 5, "reset"))
        die("live reset resource/context creation");
    for (uint32_t handle = vertex; handle <= color; handle++) {
        struct virgl_renderer_resource_info info = {0};
        if (virgl_renderer_resource_get_info((int)handle, &info) || info.handle != handle)
            die("live reset resource identity");
    }
    virgl_renderer_ctx_attach_resource(context, color);
    virgl_renderer_ctx_attach_resource(context, vertex);
    if (virgl_renderer_transfer_write_iov(vertex, context, 0, 0, 0,
        &vertex_box, 0, NULL, 0)) die("reset vertex upload");
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
}
