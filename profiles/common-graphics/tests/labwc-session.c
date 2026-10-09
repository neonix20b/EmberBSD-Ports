/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted), real EGL surface, screencopy and USB input. */
#include <sys/mman.h>
#include <err.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <wayland-client.h>
#include <wayland-egl.h>
#include "xdg-shell-client-protocol.h"
#include "wlr-screencopy-client-protocol.h"

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct wl_output *output;
static struct wl_seat *seat;
static struct wl_keyboard *keyboard;
static struct wl_pointer *pointer;
static struct xdg_wm_base *wm;
static struct zwlr_screencopy_manager_v1 *capture;
static struct wl_surface *surface;
static struct wl_egl_window *window;
static EGLDisplay egl_display;
static EGLSurface egl_surface;
static EGLContext context;
static int width = 1280, height = 800, configured, cycle;
static int key_down, key_up, button_down, button_up, motion, input_phase;
static uint32_t format, stride, shot_width, shot_height;
static struct wl_buffer *buffer;
static unsigned char *pixels;
static size_t pixel_size;
static const unsigned char colors[4][3] = {
	{255, 0, 0}, {0, 255, 0}, {0, 0, 255}, {255, 255, 0}
};
static void draw(void);
static void
ping(void *data, struct xdg_wm_base *base, uint32_t serial)
{ xdg_wm_base_pong(base, serial); }
static const struct xdg_wm_base_listener wm_listener = { .ping = ping };
static void
configure(void *data, struct xdg_surface *xdg, uint32_t serial)
{ xdg_surface_ack_configure(xdg, serial); configured = 1; }
static const struct xdg_surface_listener surface_listener = { .configure = configure };
static void
size(void *data, struct xdg_toplevel *top, int32_t w, int32_t h, struct wl_array *states)
{ if (w > 0 && h > 0) { width = w; height = h; if (window) wl_egl_window_resize(window, w, h, 0, 0); } }
static void close_window(void *data, struct xdg_toplevel *top) { errx(1, "unexpected close"); }
static const struct xdg_toplevel_listener top_listener = { .configure = size, .close = close_window };
static void keymap(void *d, struct wl_keyboard *k, uint32_t f, int fd, uint32_t n) { close(fd); }
static void key_enter(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *w, struct wl_array *a) { }
static void key_leave(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *w) { }
static void
key(void *d, struct wl_keyboard *k, uint32_t serial, uint32_t time, uint32_t code, uint32_t state)
{
	if (!input_phase || code != 37) return;
	if (state == WL_KEYBOARD_KEY_STATE_PRESSED) key_down++;
	else if (key_down) key_up++;
	printf("KEY: code=%u state=%u\n", code, state);
}
static void mods(void *d, struct wl_keyboard *k, uint32_t s, uint32_t a, uint32_t b, uint32_t c, uint32_t g) { }
static const struct wl_keyboard_listener key_listener = {
	.keymap = keymap, .enter = key_enter, .leave = key_leave, .key = key, .modifiers = mods
};
static void pointer_enter(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *w, wl_fixed_t x, wl_fixed_t y) { }
static void pointer_leave(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *w) { }
static void
pointer_motion(void *d, struct wl_pointer *p, uint32_t t, wl_fixed_t x, wl_fixed_t y)
{ if (input_phase) { motion++; printf("MOTION: x=%f y=%f\n", wl_fixed_to_double(x), wl_fixed_to_double(y)); } }
static void
button(void *d, struct wl_pointer *p, uint32_t s, uint32_t t, uint32_t b, uint32_t state)
{
	if (!input_phase || b != 272) return;
	if (state == WL_POINTER_BUTTON_STATE_PRESSED) button_down++;
	else if (button_down) button_up++;
	printf("BUTTON: code=%u state=%u\n", b, state);
}
static void axis(void *d, struct wl_pointer *p, uint32_t t, uint32_t a, wl_fixed_t v) { }
static const struct wl_pointer_listener pointer_listener = {
	.enter = pointer_enter, .leave = pointer_leave, .motion = pointer_motion, .button = button, .axis = axis
};
static void
capabilities(void *d, struct wl_seat *s, uint32_t caps)
{
	if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !keyboard) {
		keyboard = wl_seat_get_keyboard(s); wl_keyboard_add_listener(keyboard, &key_listener, NULL);
	}
	if ((caps & WL_SEAT_CAPABILITY_POINTER) && !pointer) {
		pointer = wl_seat_get_pointer(s); wl_pointer_add_listener(pointer, &pointer_listener, NULL);
	}
}
static const struct wl_seat_listener seat_listener = { .capabilities = capabilities };
static void
global(void *d, struct wl_registry *r, uint32_t name, const char *interface, uint32_t version)
{
#define BIND(iface, target) if (!strcmp(interface, #iface)) target = wl_registry_bind(r, name, &iface##_interface, 1)
	BIND(wl_compositor, compositor);
	BIND(wl_shm, shm);
	BIND(wl_output, output);
	BIND(xdg_wm_base, wm);
	BIND(zwlr_screencopy_manager_v1, capture);
	BIND(wl_seat, seat);
#undef BIND
}
static void global_remove(void *d, struct wl_registry *r, uint32_t n) { }
static const struct wl_registry_listener registry_listener = { .global = global, .global_remove = global_remove };
static void
shot_buffer(void *d, struct zwlr_screencopy_frame_v1 *frame, uint32_t f, uint32_t w, uint32_t h, uint32_t st)
{
	char path[] = "/tmp/labwc-shot.XXXXXX";
	int fd;
	struct wl_shm_pool *pool;
	if ((f != WL_SHM_FORMAT_XRGB8888 && f != WL_SHM_FORMAT_ARGB8888 &&
	    f != WL_SHM_FORMAT_XBGR8888 && f != WL_SHM_FORMAT_ABGR8888) ||
	    w < 32 || h < 32 || w > 4096 || h > 4096 || st < w * 4 || st > 32768)
		errx(1, "unsupported capture %ux%u stride=%u format=%#x", w, h, st, f);
	format = f; shot_width = w; shot_height = h; stride = st; pixel_size = (size_t)st * h;
	fd = mkstemp(path); if (fd < 0) err(1, "mkstemp"); unlink(path);
	if (ftruncate(fd, pixel_size)) err(1, "ftruncate");
	pixels = mmap(NULL, pixel_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (pixels == MAP_FAILED) err(1, "mmap");
	pool = wl_shm_create_pool(shm, fd, pixel_size);
	buffer = wl_shm_pool_create_buffer(pool, 0, w, h, st, f);
	wl_shm_pool_destroy(pool); close(fd);
	zwlr_screencopy_frame_v1_copy(frame, buffer);
}
static void shot_flags(void *d, struct zwlr_screencopy_frame_v1 *f, uint32_t flags) { }
static void shot_failed(void *d, struct zwlr_screencopy_frame_v1 *f) { errx(1, "screencopy failed"); }
static void
shot_ready(void *d, struct zwlr_screencopy_frame_v1 *f, uint32_t hi, uint32_t lo, uint32_t ns)
{
	int x, y;
	const unsigned char *rgb = colors[cycle - 1];
	for (y = shot_height / 2 - 16; y < (int)shot_height / 2 + 16; y++)
		for (x = shot_width / 2 - 16; x < (int)shot_width / 2 + 16; x++) {
			unsigned char *p = pixels + y * stride + x * 4;
			int reversed = format == WL_SHM_FORMAT_XBGR8888 || format == WL_SHM_FORMAT_ABGR8888;
			unsigned char red = p[reversed ? 0 : 2], blue = p[reversed ? 2 : 0];
			if (red != rgb[0] || p[1] != rgb[1] || blue != rgb[2])
				errx(1, "frame %d captured pixel %d,%d is %u,%u,%u", cycle, x, y, red, p[1], blue);
		}
	printf("CAPTURE: frame=%d size=%ux%u pixels=1024 rgb=%u,%u,%u\n", cycle, shot_width, shot_height, rgb[0], rgb[1], rgb[2]);
	zwlr_screencopy_frame_v1_destroy(f); wl_buffer_destroy(buffer); munmap(pixels, pixel_size);
	if (cycle < 4) draw();
	else { input_phase = 1; puts("READY_INPUT"); }
}
static const struct zwlr_screencopy_frame_v1_listener shot_listener = {
	.buffer = shot_buffer, .flags = shot_flags, .ready = shot_ready, .failed = shot_failed
};
static void
frame_done(void *d, struct wl_callback *callback, uint32_t time)
{
	struct zwlr_screencopy_frame_v1 *frame;
	wl_callback_destroy(callback);
	frame = zwlr_screencopy_manager_v1_capture_output(capture, 0, output);
	zwlr_screencopy_frame_v1_add_listener(frame, &shot_listener, NULL);
}
static const struct wl_callback_listener frame_listener = { .done = frame_done };
static void
draw(void)
{
	unsigned char p[4];
	struct wl_callback *callback;
	const unsigned char *rgb = colors[cycle++];
	glViewport(0, 0, width, height);
	glClearColor(rgb[0] / 255.0f, rgb[1] / 255.0f, rgb[2] / 255.0f, 1);
	glClear(GL_COLOR_BUFFER_BIT);
	glReadPixels(width / 2, height / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p);
	if (glGetError() != GL_NO_ERROR || memcmp(p, rgb, 3)) errx(1, "client EGL pixel mismatch");
	callback = wl_surface_frame(surface); wl_callback_add_listener(callback, &frame_listener, NULL);
	if (!eglSwapBuffers(egl_display, egl_surface)) errx(1, "eglSwapBuffers: %#x", eglGetError());
}
int
main(void)
{
	EGLConfig config;
	EGLint count, major, minor;
	struct wl_registry *registry;
	struct xdg_surface *xdg;
	struct xdg_toplevel *top;
	const char *renderer;
	const EGLint attributes[] = { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE };
	const EGLint context_attributes[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	setvbuf(stdout, NULL, _IONBF, 0); alarm(55);
	display = wl_display_connect(NULL); if (!display) errx(1, "Wayland connection failed");
	registry = wl_display_get_registry(display); wl_registry_add_listener(registry, &registry_listener, NULL);
	if (wl_display_roundtrip(display) < 0 || !compositor || !shm || !output || !wm || !capture || !seat)
		errx(1, "missing Wayland globals");
	xdg_wm_base_add_listener(wm, &wm_listener, NULL); wl_seat_add_listener(seat, &seat_listener, NULL);
	if (wl_display_roundtrip(display) < 0 || !keyboard || !pointer) errx(1, "missing input capabilities");
	surface = wl_compositor_create_surface(compositor); xdg = xdg_wm_base_get_xdg_surface(wm, surface);
	xdg_surface_add_listener(xdg, &surface_listener, NULL); top = xdg_surface_get_toplevel(xdg);
	xdg_toplevel_add_listener(top, &top_listener, NULL); xdg_toplevel_set_title(top, "EmberBSD EGL acceptance");
	xdg_toplevel_set_app_id(top, "emberbsd-labwc-acceptance"); xdg_toplevel_set_fullscreen(top, output);
	wl_surface_commit(surface);
	while (!configured) if (wl_display_dispatch(display) < 0) errx(1, "configure failed");
	window = wl_egl_window_create(surface, width, height);
	egl_display = eglGetDisplay((EGLNativeDisplayType)display);
	if (!eglInitialize(egl_display, &major, &minor) || !eglBindAPI(EGL_OPENGL_ES_API) ||
	    !eglChooseConfig(egl_display, attributes, &config, 1, &count) || count != 1) errx(1, "EGL initialization");
	context = eglCreateContext(egl_display, config, EGL_NO_CONTEXT, context_attributes);
	egl_surface = eglCreateWindowSurface(egl_display, config, (EGLNativeWindowType)window, NULL);
	if (context == EGL_NO_CONTEXT || egl_surface == EGL_NO_SURFACE ||
	    !eglMakeCurrent(egl_display, egl_surface, egl_surface, context)) errx(1, "EGL surface/context");
	renderer = (const char *)glGetString(GL_RENDERER);
	if (!renderer || strcmp(renderer, "virgl")) errx(1, "wrong renderer: %s", renderer ? renderer : "null");
	printf("CLIENT_RENDERER: %s\n", renderer); draw();
	while (!(key_down && key_up && button_down && button_up && motion))
		if (wl_display_dispatch(display) < 0) errx(1, "dispatch failed");
	eglMakeCurrent(egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	eglDestroySurface(egl_display, egl_surface); eglDestroyContext(egl_display, context); eglTerminate(egl_display);
	wl_egl_window_destroy(window); xdg_toplevel_destroy(top); xdg_surface_destroy(xdg); wl_surface_destroy(surface);
	wl_keyboard_destroy(keyboard); wl_pointer_destroy(pointer); wl_seat_destroy(seat);
	zwlr_screencopy_manager_v1_destroy(capture); xdg_wm_base_destroy(wm);
	wl_output_destroy(output); wl_shm_destroy(shm); wl_compositor_destroy(compositor); wl_registry_destroy(registry);
	wl_display_flush(display); wl_display_disconnect(display); alarm(0);
	puts("PASS: four EGL frames, screencopy pixels, USB keyboard/pointer delivery, client cleanup");
	return 0;
}
