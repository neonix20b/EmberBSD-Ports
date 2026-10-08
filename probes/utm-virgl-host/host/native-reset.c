/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD, AI-assisted real Metal reset/lifetime probe; no simulated renderer. */
#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <virglrenderer.h>
#include <virgl_hw.h>
#include <pipe/p_defines.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/uio.h>
#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>

struct state {
    EGLDisplay display;
    EGLConfig config;
    EGLSurface surface;
    EGLContext anchor;
    EGLContext contexts[16];
    unsigned live;
    uint32_t fence, expected_fence, cancelled[3];
    unsigned callbacks, created, destroyed, generation[16];
};

static _Noreturn void die(const char *what)
{
    fprintf(stderr, "FAIL: %s (EGL %#x)\n", what, eglGetError());
    exit(1);
}
static virgl_renderer_gl_context create_context(void *opaque, int scanout,
    struct virgl_renderer_gl_ctx_param *param)
{
    struct state *s = opaque;
    (void)scanout;
    const EGLint attr[] = {EGL_CONTEXT_MAJOR_VERSION, param->major_ver,
        EGL_CONTEXT_MINOR_VERSION, param->minor_ver, EGL_NONE};
    EGLContext c = eglCreateContext(s->display, s->config,
        param->shared ? eglGetCurrentContext() : EGL_NO_CONTEXT, attr);
    if (c != EGL_NO_CONTEXT) {
        unsigned slot;
        for (slot = 0; slot < 16 && s->contexts[slot]; slot++) {}
        if (slot == 16) die("context registry capacity");
        s->contexts[slot] = c;
        s->live++;
        s->generation[slot] = ++s->created;
    }
    else (void)eglGetError();
    return c;
}
static void destroy_context(void *opaque, virgl_renderer_gl_context context)
{
    struct state *s = opaque;
    unsigned slot;
    if (context == EGL_NO_CONTEXT) die("destroy of absent context");
    for (slot = 0; slot < 16 && s->contexts[slot] != context; slot++) {}
    if (slot == 16) die("destroy of unowned context");
    if (eglGetCurrentContext() == context &&
        !eglMakeCurrent(s->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT))
        die("release current context");
    if (!eglDestroyContext(s->display, context) || s->live == 0)
        die("context ownership");
    s->contexts[slot] = EGL_NO_CONTEXT;
    s->live--;
    s->destroyed++;
}
static int make_current(void *opaque, int scanout, virgl_renderer_gl_context c)
{
    struct state *s = opaque;
    (void)scanout;
    return eglMakeCurrent(s->display, s->surface, s->surface, c) ? 0 : -EIO;
}
static void write_fence(void *opaque, uint32_t fence)
{
    struct state *s = opaque;
    for (unsigned i = 0; i < 3; i++)
        if (s->cancelled[i] == fence) die("cancelled fence callback after reset");
    if (!fence || fence != s->expected_fence) die("unexpected fence callback");
    s->callbacks++;
    s->fence = fence;
}
static void write_context_fence(void *opaque, uint32_t context, uint32_t ring,
    uint64_t fence)
{
    (void)opaque; (void)context; (void)ring; (void)fence;
    die("unexpected context fence");
}
static void *get_display(void *opaque)
{
    return ((struct state *)opaque)->display;
}
#include "native-draw.h"
#include "native-reset-scene.h"
/* Check resolved images, not just the linker's intended install names. */
static void check_image(const char *symbol, const char *directory, const char *file)
{
    Dl_info info;
    char expected[PATH_MAX], actual[PATH_MAX], path[PATH_MAX];
    void *entry = dlsym(RTLD_DEFAULT, symbol);
    int n = snprintf(path, sizeof(path), "%s/%s", directory, file);
    if (n < 0 || (size_t)n >= sizeof(path) || !entry || !dladdr(entry, &info) ||
        !realpath(path, expected) || !realpath(info.dli_fname, actual) ||
        strcmp(expected, actual)) die("resolved library identity");
    printf("loaded %s=%s\n", symbol, actual);
}
static void check_framework(const char *directory, const char *name)
{
    char path[PATH_MAX], expected[PATH_MAX], actual[PATH_MAX];
    int n = snprintf(path, sizeof(path), "%s/%s.framework/%s", directory, name, name);
    if (n < 0 || (size_t)n >= sizeof(path) || !realpath(path, expected))
        die("framework path");
    unsigned matches = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (realpath(_dyld_get_image_name(i), actual) && !strcmp(actual, expected))
            matches++;
    }
    if (matches != 1) die("expected framework not loaded exactly once");
    printf("loaded framework=%s\n", expected);
}
int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (argc != 3) return 2;
    check_image("virgl_renderer_reset", argv[1], "libvirglrenderer.1.dylib");
    check_image("virgl_renderer_ember_classic_poll_v1", argv[1], "libvirglrenderer.1.dylib");
    check_image("epoxy_gl_version", argv[1], "libepoxy.0.dylib");
    struct state s = {0};
    (void)eglGetError();
    printf("EGL client extensions=%s\n", eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS));
    const EGLint display_attrs[] = {EGL_PLATFORM_ANGLE_TYPE_ANGLE,
        EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE, EGL_NONE};
    s.display = eglGetPlatformDisplayEXT(EGL_PLATFORM_ANGLE_ANGLE,
        NULL, display_attrs);
    printf("EGL display=%p error=%#x\n", s.display, eglGetError());
    EGLint major, minor;
    if (s.display == EGL_NO_DISPLAY || !eglInitialize(s.display, &major, &minor))
        die("initialize Metal EGL display");
    printf("EGL %d.%d vendor=%s\n", major, minor,
        eglQueryString(s.display, EGL_VENDOR));
    const EGLint config_attrs[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
    EGLint count;
    if (!eglBindAPI(EGL_OPENGL_ES_API) ||
        !eglChooseConfig(s.display, config_attrs, &s.config, 1, &count) || count != 1)
        die("choose GLES configuration");
    const EGLint surface_attrs[] = {EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE};
    const EGLint context_attrs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    s.surface = eglCreatePbufferSurface(s.display, s.config, surface_attrs);
    s.anchor = eglCreateContext(s.display, s.config, EGL_NO_CONTEXT, context_attrs);
    if (s.surface == EGL_NO_SURFACE || s.anchor == EGL_NO_CONTEXT ||
        !eglMakeCurrent(s.display, s.surface, s.surface, s.anchor)) die("GLES context");
    const char *renderer = (const char *)glGetString(GL_RENDERER);
    printf("GL renderer=%s; version=%s\n", renderer, glGetString(GL_VERSION));
    if (!renderer || !strstr(renderer, "Metal") || !strstr(renderer, "Apple") ||
        strstr(renderer, "Software") || strstr(renderer, "llvmpipe"))
        die("hardware Metal renderer identity");
    glClearColor(0.25f, 0.5f, 0.75f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    unsigned char pixels[16 * 16 * 4];
    glReadPixels(0, 0, 16, 16, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    if (glGetError() != GL_NO_ERROR) die("readback GL error");
    for (unsigned i = 0; i < sizeof(pixels); i += 4) {
        if (abs((int)pixels[i] - 64) > 1 || abs((int)pixels[i+1] - 128) > 1 ||
            abs((int)pixels[i+2] - 191) > 1 || pixels[i+3] != 255) die("pixel mismatch");
    }
    check_framework(argv[2], "EGL");
    check_framework(argv[2], "GLESv2");
    puts("PASS: 256 Metal EGL pixels");
    struct virgl_renderer_callbacks cb = {.version = 4, .write_fence = write_fence,
        .create_gl_context = create_context, .destroy_gl_context = destroy_context,
        .make_current = make_current, .write_context_fence = write_context_fence,
        .get_egl_display = get_display};
    if (virgl_renderer_ember_classic_init_v1(&s, 0, &cb)) die("classic reset init");
    if (s.live != 1 || virgl_renderer_ember_classic_wait_status_v1())
        die("initial ctx0 ownership/status");
    struct reset_scene scenes[3], snapshots[3];
    for (unsigned cycle = 1; cycle <= 3; cycle++) {
        struct reset_scene *scene = &scenes[cycle - 1], *saved = &snapshots[cycle - 1];
        unsigned callbacks = s.callbacks;
        reset_scene_submit(scene);
        if (s.live < 2) die("live user GL context before reset");
        memcpy(saved, scene, sizeof(*scene));
        const uint32_t pending = 900 + cycle;
        s.fence = 0;
        s.expected_fence = pending;
        if (virgl_renderer_create_fence((int)pending, 8) || glGetError() != GL_NO_ERROR)
            die("live reset fence creation");
        /* No polling, readback, GL wait or glFinish occurs between fence
         * creation and reset. GPU completion itself is not observable here. */
        if (s.fence || s.callbacks != callbacks) die("fence already reported before reset");
        s.cancelled[cycle - 1] = pending;
        s.expected_fence = 0;
        unsigned created = s.created, destroyed = s.destroyed, live = s.live;
        printf("reset cycle %u: live GL contexts=%u, resources=2, attached IOVs=2, unreported fence=%u\n",
            cycle, live, pending);
        virgl_renderer_reset();
        if (s.live != 1 || s.created != created + 1 || s.destroyed != destroyed + live)
            die("reset GL context ownership and ctx0 replacement");
        for (unsigned slot = 0; slot < 16; slot++)
            if (s.contexts[slot] && s.generation[slot] <= created)
                die("old GL context survived reset");
        if (s.callbacks != callbacks || virgl_renderer_ember_classic_wait_status_v1())
            die("reset fence/status contract");
        uint32_t nop = VIRGL_CMD0(VIRGL_CCMD_NOP, 0, 0);
        if (virgl_renderer_submit_cmd(&nop, 8, 1) != EINVAL)
            die("old context accepted after reset");
        for (uint32_t handle = 2; handle <= 3; handle++) {
            struct virgl_renderer_resource_info info = {0};
            if (virgl_renderer_resource_get_info((int)handle, &info) != EINVAL)
                die("old resource survived reset");
            struct iovec *detached = &scene->color_iov;
            int count = 99;
            virgl_renderer_resource_detach_iov((int)handle, &detached, &count);
            if (detached != &scene->color_iov || count != 99)
                die("absent resource detach changed outputs");
        }
        /* Polling an empty post-reset queue must never emit the old fence. */
        for (unsigned poll = 0; poll < 4; poll++)
            if (virgl_renderer_ember_classic_poll_v1() || s.callbacks != callbacks)
                die("post-reset empty poll");
        if (memcmp(scene, saved, sizeof(*scene))) die("reset modified caller IOV storage");
        s.expected_fence = 500 + cycle;
        /* Reuse exactly ctx8/resources2,3 and all shader/state handles.
         * This submits fresh shaders, a real fence and the existing pixel oracle. */
        check_virgl_draw(&s, cycle);
        if (s.callbacks != callbacks + 1 || s.fence != s.expected_fence || s.live != 1)
            die("post-reset render fence/ownership");
        for (unsigned retired = 0; retired < cycle; retired++)
            if (memcmp(&scenes[retired], &snapshots[retired], sizeof(scenes[retired])))
                die("later rendering modified retired caller IOVs");
        puts("PASS: reset removed old contexts/resources/fence; ID reuse and fresh shader pixels pass");
    }
    virgl_renderer_cleanup(&s);
    for (unsigned retired = 0; retired < 3; retired++)
        if (memcmp(&scenes[retired], &snapshots[retired], sizeof(scenes[retired])))
            die("final cleanup modified retired caller IOVs");
    if (s.live || s.created != s.destroyed ||
        virgl_renderer_ember_classic_wait_status_v1() != -EINVAL)
        die("final renderer cleanup ownership/status");
    if (!eglMakeCurrent(s.display, s.surface, s.surface, s.anchor))
        die("borrowed EGL anchor after reset/cleanup");
    glClearColor(0, 0, 1, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    unsigned char anchor_pixel[4];
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, anchor_pixel);
    if (glGetError() != GL_NO_ERROR || anchor_pixel[0] || anchor_pixel[1] ||
        anchor_pixel[2] != 255 || anchor_pixel[3] != 255)
        die("borrowed anchor pixel after cleanup");
    if (!eglMakeCurrent(s.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT) ||
        !eglDestroyContext(s.display, s.anchor) || !eglDestroySurface(s.display, s.surface) ||
        !eglTerminate(s.display)) die("EGL cleanup after reset");
    printf("PASS: three real Metal reset lifecycles; %u owned GL contexts created/destroyed, %u fresh fence callbacks\n",
        s.created, s.callbacks);
    puts("Boundary: unreported fences, not proof of physically incomplete GPU work, guest reset or DMA revocation");
    return 0;
}
