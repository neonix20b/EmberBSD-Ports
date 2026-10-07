/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD, AI-assisted native EGL/Metal and classic renderer probe. */
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
    uint32_t fence;
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
    if (argc != 3) return 2;
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
    for (unsigned cycle = 1; cycle <= 3; cycle++) {
        int ret = virgl_renderer_ember_classic_init_v1(&s, 0, &cb);
        if (ret) { fprintf(stderr, "renderer init=%d\n", ret); die("classic init"); }
        if (virgl_renderer_ember_classic_init_v1(&s, 0, &cb) != -EBUSY)
            die("live reinitialization was accepted");
        uint32_t version = 0, size = 0;
        virgl_renderer_get_cap_set(1, &version, &size);
        if (!version || !size) die("classic capset");
        printf("caps version=%u size=%u\n", version, size);
        unsigned char source[16 * 16 * 4], backing[sizeof(source)];
        for (unsigned i = 0; i < sizeof(source); i++)
            source[i] = (unsigned char)((i * 37 + cycle * 19) & 255);
        memcpy(backing, source, sizeof(source));
        struct iovec iov = {backing, sizeof(backing)};
        struct virgl_box box = {0, 0, 0, 16, 16, 1};
        struct virgl_renderer_resource_create_args resource = {
            .handle = 1, .target = PIPE_TEXTURE_2D,
            .format = VIRGL_FORMAT_R8G8B8A8_UNORM,
            .bind = VIRGL_BIND_RENDER_TARGET | VIRGL_BIND_SAMPLER_VIEW,
            .width = 16, .height = 16, .depth = 1, .array_size = 1
        };
        if (virgl_renderer_resource_create(&resource, NULL, 0))
            die("VirGL RGBA resource create");
        if (virgl_renderer_resource_attach_iov(1, &iov, 1)) die("VirGL IOV attach");
        if (virgl_renderer_transfer_write_iov(1, 0, 0, 64, 0, &box, 0, NULL, 0))
            die("VirGL RGBA transfer write");
        memset(backing, 0, sizeof(backing));
        if (virgl_renderer_transfer_read_iov(1, 0, 0, 64, 0, &box, 0, NULL, 0))
            die("VirGL RGBA transfer read");
        if (glGetError() != GL_NO_ERROR) die("VirGL transfer GL error");
        if (memcmp(source, backing, sizeof(source))) die("VirGL RGBA mismatch");
        struct iovec *detached = NULL;
        int detached_count = 0;
        virgl_renderer_resource_detach_iov(1, &detached, &detached_count);
        if (detached != &iov || detached_count != 1) die("IOV detach ownership");
        virgl_renderer_resource_unref(1);
        puts("PASS: 256 VirGL texture pixels and backing detach");
        s.fence = 0;
        if (virgl_renderer_create_fence((int)cycle, 0)) die("create native fence");
        for (unsigned poll = 0; s.fence != cycle && poll < 2000; poll++) {
            if (virgl_renderer_ember_classic_poll_v1()) die("checked native poll");
            if (s.fence != cycle) usleep(1000);
        }
        if (s.fence != cycle) die("native fence deadline");
        virgl_renderer_cleanup(&s);
        if (s.live != 0 || virgl_renderer_ember_classic_wait_status_v1() != -EINVAL)
            die("renderer cleanup ownership");
        if (!eglMakeCurrent(s.display, s.surface, s.surface, s.anchor))
            die("borrowed EGL display after renderer cleanup");
        printf("PASS: classic init/fence/poll/cleanup cycle %u\n", cycle);
    }
    if (!eglMakeCurrent(s.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT) ||
        !eglDestroyContext(s.display, s.anchor) || !eglDestroySurface(s.display, s.surface) ||
        !eglTerminate(s.display)) die("EGL cleanup");
    return 0;
}
