/* SPDX-License-Identifier: GPL-2.0-or-later
 * Origin: EmberBSD (AI-assisted), QEMU source-derived context ownership checks.
 * Included bodies retain QEMU's copyright/license notices. Only GL operations,
 * display embedding and resource metadata are modeled; this is not a GPU test.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CONFIG_EGL 1
#define CONFIG_METAL 1
#define VIRGL_VERSION_MAJOR 1
#define VIRGL_RENDERER_RESOURCE_INFO_EXT_VERSION 1
#define NATIVE_HANDLE_SUPPORT_VERSION 1
#define EGL_NO_SURFACE 0
#define EGL_NO_CONTEXT 0
#define EGL_DRAW 1
#define EGL_READ 2
#define kCGLNoError 0
#define SCANOUT_TEXTURE_NATIVE_TYPE_NONE 0
#define SCANOUT_TEXTURE_NATIVE_TYPE_D3D 1
#define SCANOUT_TEXTURE_NATIVE_TYPE_METAL 2
#define VIRGL_NATIVE_HANDLE_NONE 0
#define VIRGL_NATIVE_HANDLE_D3D_TEX2D 1
#define VIRGL_NATIVE_HANDLE_METAL_TEXTURE 2
#define VIRTIO_GPU_RESOURCE_FLAG_Y_0_TOP 1
#define VIRTIO_GPU_RESP_ERR_INVALID_SCANOUT_ID 1
#define VIRTIO_GPU_RESP_ERR_INVALID_RESOURCE_ID 2
#define LOG_GUEST_ERROR 0
#define qemu_log_mask(...) ((void)0)
#define trace_virtio_gpu_cmd_set_scanout(...) ((void)0)
#define qatomic_set(p,v) (*(p)=(v))

typedef uintptr_t EGLDisplay;
typedef uintptr_t EGLContext;
typedef uintptr_t EGLSurface;
typedef void *CGLContextObj;
typedef void (^CodeBlock)(void);
struct current_state {
	uintptr_t display, context, draw, read;
};
static struct current_state current;
static uintptr_t gl_view_ctx = 200, egl_surface = 1, qemu_egl_display = 1;
static unsigned switches, null_binds, texture_work, block_calls, fail_call;
static bool gl_dirty;
static struct { void *gls; } dgc;
typedef struct { int width, height; } DisplaySurface;
typedef struct { int unused; } DisplayChangeListener;
static DisplaySurface placeholder = {640, 480}, *surface = &placeholder;
static DisplayChangeListener listener;

static bool
state_equal(struct current_state a, struct current_state b)
{
	return a.display == b.display && a.context == b.context &&
	    a.draw == b.draw && a.read == b.read;
}

static uintptr_t
get_surface(int selector)
{
	return selector == EGL_DRAW ? current.draw : current.read;
}
#define eglGetCurrentDisplay() (current.display)
#define eglGetCurrentContext() (current.context)
#define eglGetCurrentSurface(selector) get_surface(selector)
#define CGLGetCurrentContext() ((CGLContextObj)current.context)

static int
eglMakeCurrent(uintptr_t display, uintptr_t draw, uintptr_t read, uintptr_t ctx)
{
	switches++;
	/* EGL_NO_DISPLAY is not a valid display for unbinding a context. */
	if (switches == fail_call || display == 0 || (!ctx && (draw || read)))
		return 0;
	current = ctx ? (struct current_state){display, ctx, draw, read} :
	    (struct current_state){0, 0, 0, 0};
	null_binds += ctx == 0;
	return 1;
}

static int
CGLSetCurrentContext(CGLContextObj ctx)
{
	switches++;
	if (switches == fail_call)
		return 1;
	current.context = (uintptr_t)ctx;
	return kCGLNoError;
}

static void
error_report(const char *message)
{
	fprintf(stderr, "%s; switches=%u block_calls=%u\n", message,
	    switches, block_calls);
}

static void
surface_gl_destroy_texture(void *gls, DisplaySurface *s)
{
	(void)gls;
	(void)s;
	texture_work++;
}

static void
surface_gl_create_texture(void *gls, DisplaySurface *s)
{
	(void)gls;
	(void)s;
	texture_work++;
}

static void
surface_gl_update_texture(void *gls, DisplaySurface *s, int x, int y, int w, int h)
{
	(void)gls;
	(void)s;
	(void)x;
	(void)y;
	(void)w;
	(void)h;
	texture_work++;
}

static void
cocoa_switch(DisplayChangeListener *dcl, DisplaySurface *s)
{
	(void)dcl;
	surface = s;
}

#include "cocoa-body.h"

/* console.c invokes these callbacks synchronously when the new surface is
 * NULL: displaychangelistener_gfx_switch(..., update=true). */
static void
dpy_gfx_replace_surface(void *con, void *s)
{
	(void)con;
	(void)s;
	cocoa_gl_switch(&listener, &placeholder);
	cocoa_gl_update(&listener, 0, 0, placeholder.width, placeholder.height);
}

static void
qemu_console_resize(void *con, unsigned w, unsigned h)
{
	placeholder.width = w;
	placeholder.height = h;
	dpy_gfx_replace_surface(con, NULL);
}

static void
virgl_renderer_force_ctx_0(void)
{
	current = (struct current_state){1, 100, 1, 1};
}

typedef struct { int type; void *handle; } ScanoutTextureNative;
#define NO_NATIVE_TEXTURE ((ScanoutTextureNative){0, NULL})
static void dpy_gl_scanout_disable(void *c) { (void)c; }
static void
dpy_gl_scanout_texture(void *c, unsigned id, bool top, unsigned bw, unsigned bh,
    unsigned x, unsigned y, unsigned w, unsigned h, ScanoutTextureNative n,
    void *unused)
{
	(void)c; (void)id; (void)top; (void)bw; (void)bh; (void)x; (void)y;
	(void)w; (void)h; (void)n; (void)unused;
}
struct virgl_renderer_resource_info { unsigned tex_id, flags, width, height; };
struct virgl_renderer_resource_info_ext {
	struct virgl_renderer_resource_info base;
	void *d3d_tex2d, *native_handle;
	int native_type;
	unsigned version;
};
static int
virgl_renderer_resource_get_info_ext(unsigned id,
    struct virgl_renderer_resource_info_ext *ext)
{
	(void)id;
	ext->base = (struct virgl_renderer_resource_info){1, 0, 1280, 800};
	ext->version = 1;
	return 0;
}
struct virtio_gpu_set_scanout {
	unsigned scanout_id, resource_id;
	struct { unsigned width, height, x, y; } r;
};
struct virtio_gpu_ctrl_command { int error; struct virtio_gpu_set_scanout input; };
typedef struct {
	struct {
		unsigned enable;
		struct { unsigned max_outputs; } conf;
		struct { void *con; unsigned resource_id; } scanout[1];
	} parent_obj;
} VirtIOGPU;
#define VIRTIO_GPU_FILL_CMD(v) ((v) = cmd->input)

#include "scanout-body.h"

static void
require_view(void)
{
	block_calls++;
	if (current.context != gl_view_ctx) {
		fputs("FAIL: callback has wrong display context\n", stderr);
		exit(3);
	}
}

int
main(int argc, char **argv)
{
	if (argc != 2)
		return 2;
	const char *mode = argv[1];
	virgl_renderer_force_ctx_0();
	if (strncmp(mode, "scanout-", 8) == 0) {
		VirtIOGPU gpu = {0};
		struct virtio_gpu_ctrl_command cmd = {0};
		gpu.parent_obj.conf.max_outputs = 1;
		if (strcmp(mode, "scanout-enabled") == 0)
			cmd.input.resource_id = 1;
		else if (strcmp(mode, "scanout-disabled") != 0 &&
		    strcmp(mode, "scanout-mode-set-nofb") != 0)
			return 2;
		if (strcmp(mode, "scanout-disabled") != 0) {
			cmd.input.r.width = 1280;
			cmd.input.r.height = 800;
		}
		virgl_cmd_set_scanout(&gpu, &cmd);
		printf("%s: context=%lu switches=%u null_binds=%u work=%u error=%d\n",
		    mode, (unsigned long)current.context, switches, null_binds,
		    texture_work, cmd.error);
		if (cmd.error || texture_work != 3)
			return 3;
		/* This is the next fence boundary in the actual QEMU dispatch.
		 * A current context is necessary, but no GL fence is simulated. */
		if (current.context != 100) {
			fputs("FAIL: scanout lost renderer context before fence\n", stderr);
			return 1;
		}
	} else {
		bool cgl = strncmp(mode, "cgl-", 4) == 0;
		if (cgl)
			egl_surface = 0;
		if (strstr(mode, "none"))
			current = (struct current_state){0, 0, 0, 0};
		else if (!cgl)
			current = (struct current_state){9, 123, 11, 12};
		if (strstr(mode, "enter-fail"))
			fail_call = 1;
		else if (strstr(mode, "restore-fail"))
			fail_call = 2;
		struct current_state previous = current;
		with_gl_view_ctx(^{
			require_view();
			if (strstr(mode, "nested")) {
				struct current_state outer = current;
				with_gl_view_ctx(^{ require_view(); });
				if (!state_equal(outer, current)) {
					fputs("FAIL: nested callback lost outer context\n", stderr);
					exit(3);
				}
			}
		});
		if (fail_call) {
			fputs("FAIL: failed context switch returned to caller\n", stderr);
			return 3;
		}
		if (!state_equal(previous, current)) {
			fputs("FAIL: previous context tuple was not restored\n", stderr);
			return 1;
		}
	}
	puts("PASS: actual source context ownership; GL primitives modeled");
	return 0;
}
