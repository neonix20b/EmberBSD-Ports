/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted). Deterministic external API boundary doubles. */
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WLR_ERROR 1
#define WLR_DEBUG 2
#define WLR_HAS_GBM_ALLOCATOR 1
#define WLR_HAS_GLES2_RENDERER 1
#define WLR_HAS_UDMABUF_ALLOCATOR 0
#define WLR_BUFFER_CAP_DMABUF 1
#define WLR_BUFFER_CAP_DATA_PTR 2
#define WLR_BUFFER_CAP_SHM 4
#define DRM_NODE_PRIMARY 1
#define DRM_NODE_RENDER 2
#define EGL_NO_DEVICE_EXT NULL
#define EGL_PLATFORM_DEVICE_EXT 1
#define EGL_PLATFORM_GBM_KHR 2
#define EGL_NO_SURFACE 0
#define EGL_NO_CONTEXT 0

typedef void *EGLDeviceEXT;
typedef int EGLenum;
typedef int EGLint;
typedef int EGLDisplay;
typedef unsigned drm_magic_t;
#define EGL_NO_DISPLAY 0
#define EGL_TRACK_REFERENCES_KHR 1
#define EGL_TRUE 1
#define EGL_NONE 0
#define EGL_CONTEXT_CLIENT_VERSION 1
#define EGL_CONTEXT_PRIORITY_LEVEL_IMG 2
#define EGL_CONTEXT_PRIORITY_HIGH_IMG 3
#define EGL_CONTEXT_PRIORITY_MEDIUM_IMG 4
#define EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY_EXT 5
#define EGL_LOSE_CONTEXT_ON_RESET_EXT 6
#define EGL_NO_CONFIG_KHR 0
#define WLR_INFO 3

struct gbm_device { int fd; };
struct wlr_egl {
	int display, context; struct { EGLDisplay (*eglGetPlatformDisplayEXT)(EGLenum, void *, const EGLint *); } procs;
	struct gbm_device *gbm_device;
	struct {
		bool EXT_platform_device, KHR_platform_gbm;
		bool MESA_device_software, KHR_display_reference, IMG_context_priority, EXT_create_context_robustness;
	} exts;
	int dmabuf_render_formats, dmabuf_texture_formats;
};
struct wlr_backend { uint32_t buffer_caps; };
struct wlr_renderer { uint32_t render_buffer_caps; struct wlr_egl *egl; };
struct wlr_allocator { int fd; };
static struct wlr_allocator allocator;
static bool software, fail_dup, fail_retry_create, fail_retry_init, no_render, have_reference;
static bool fail_display, no_display, fail_open, fail_auth;
static int types[256], next_fd, opened, closed, objects, devices, contexts;
static int tables[256], next_table, names;
static void *egl_objects[8];
static int creates, inits, destroys, releases, device_queries, duplicates;
static bool last_allow_render;
static char cleanup[256];
static size_t cleanup_len;
static int formats, live_displays;
static bool displays[8];
static EGLDisplay fake_get_display(EGLenum platform, void *remote, const EGLint *attrs) {
	(void)platform; (void)remote; (void)attrs;
	inits++;
	return no_display && inits == 2 ? EGL_NO_DISPLAY : inits;
}


static void event(char e) { cleanup[cleanup_len++] = e; cleanup[cleanup_len] = '\0'; }
static int new_fd(int type) { assert(next_fd < 256); types[next_fd] = type; tables[next_fd] = ++next_table; opened++; return next_fd++; }
static int fake_close(int fd) { assert(fd != 10 && fd != 11 && types[fd]); types[fd] = 0; closed++; event('F'); return 0; }
static int fake_fcntl(int fd, int op, int minimum) {
	assert(types[fd] && op == F_DUPFD_CLOEXEC && minimum == 0);
	duplicates++;
	if (fail_dup) return -1;
	int dup_fd = new_fd(types[fd]); tables[dup_fd] = tables[fd]; return dup_fd;
}
static int drmGetNodeTypeFromFd(int fd) { return types[fd]; }
static char *drmGetRenderDeviceNameFromFd(int fd) { assert(types[fd]); if (no_render) return NULL; names++; return strdup("render"); }
static char *drmGetPrimaryDeviceNameFromFd(int fd) { assert(types[fd]); names++; return strdup("primary"); }
static char *drmGetDeviceNameFromFd2(int fd) { assert(types[fd]); names++; return strdup(types[fd] == DRM_NODE_PRIMARY ? "primary" : "render"); }
static int fake_open(const char *name, int flags) {
	assert(flags == (O_RDWR | O_CLOEXEC));
	if (fail_open && strcmp(name, "primary") == 0) return -1;
	return new_fd(strcmp(name, "primary") == 0 ? DRM_NODE_PRIMARY : DRM_NODE_RENDER);
}
static bool drmIsMaster(int fd) { return fd == 10; }
static int drmGetMagic(int fd, drm_magic_t *magic) { assert(types[fd] == DRM_NODE_PRIMARY); *magic = (unsigned)fd; return 0; }
static int drmAuthMagic(int fd, drm_magic_t magic) { assert(fd == 10 && types[magic] == DRM_NODE_PRIMARY); return fail_auth ? -1 : 0; }
static void wlr_log(int level, const char *format, ...) { (void)level; (void)format; }
#define wlr_log_errno wlr_log
static struct wlr_egl *egl_create(void) {
	creates++;
	if (creates == 2 && fail_retry_create) return NULL;
	struct wlr_egl *egl = calloc(1, sizeof(*egl));
	assert(egl); objects++;
	egl_objects[creates] = egl;
	egl->procs.eglGetPlatformDisplayEXT = fake_get_display; egl->exts.KHR_platform_gbm = true;
	egl->exts.KHR_display_reference = have_reference;
	return egl;
}
static struct gbm_device *gbm_create_device(int fd) {
	struct gbm_device *gbm = calloc(1, sizeof(*gbm));
	assert(gbm); devices++; gbm->fd = fd; return gbm;
}
static int gbm_device_get_fd(struct gbm_device *gbm) { return gbm->fd; }
static void gbm_device_destroy(struct gbm_device *gbm) { assert(devices > 0); devices--; event('B'); free(gbm); }
static void tracked_free(void *p) {
	for (int i = 1; i <= creates; i++) {
		if (egl_objects[i] == p) { egl_objects[i] = NULL; objects--; event('E'); free(p); return; }
	}
	assert(names > 0); names--; free(p);
}
static EGLDeviceEXT get_egl_device_from_drm_fd(struct wlr_egl *egl, int fd) { (void)egl; (void)fd; return NULL; }
static bool egl_init_display(struct wlr_egl *egl, EGLDisplay display, bool allow) {
  (void)allow; egl->display = display; live_displays++; displays[display] = true;
  egl->exts.MESA_device_software = software;
  egl->dmabuf_render_formats = egl->dmabuf_texture_formats = 1; formats += 2;
  return !(inits == 2 && fail_display);
}
static int eglCreateContext(int display, int config, int shared, const EGLint *attrs) {
  (void)display; (void)config; (void)shared; (void)attrs;
  if (inits == 2 && fail_retry_init) return EGL_NO_CONTEXT;
  contexts++; return 1;
}
static bool eglQueryContext(int display, int context, int attribute, EGLint *value) {
  (void)display; (void)context; (void)attribute; (void)value; return true;
}
static void eglTerminate(int display);
static void wlr_drm_format_set_finish(int *format) { formats -= *format; *format = 0; }
static void eglMakeCurrent(int display, int draw, int read, int context) { (void)display; (void)draw; (void)read; (void)context; }
static void eglDestroyContext(int display, int context) { assert(display && context && contexts > 0); contexts--; event('C'); }
static void eglTerminate(int display) { assert(display && displays[display]); displays[display] = false; live_displays--; event('T'); }
static void eglReleaseThread(void) { releases++; }
static int dup_egl_device_drm_fd(struct wlr_egl *egl) { (void)egl; device_queries++; return new_fd(DRM_NODE_RENDER); }
static bool wlr_renderer_is_gles2(struct wlr_renderer *r) { (void)r; return true; }
static struct wlr_egl *wlr_gles2_renderer_get_egl(struct wlr_renderer *r) { return r->egl; }
static int wlr_egl_dup_drm_fd(struct wlr_egl *egl);
static void wlr_egl_destroy(struct wlr_egl *egl);
static void egl_destroy(struct wlr_egl *egl, bool terminate_display);
static int wlr_renderer_get_drm_fd(struct wlr_renderer *r) { return gbm_device_get_fd(r->egl->gbm_device); }
static int wlr_backend_get_drm_fd(struct wlr_backend *b) { (void)b; return 10; }
static int open_render_node(int fd);
int reopen_drm_node(int fd, bool allow_render);
static struct wlr_allocator *wlr_gbm_allocator_create(int fd) { allocator.fd = fd; return &allocator; }
static struct wlr_allocator *wlr_shm_allocator_create(void) { assert(false); return NULL; }
static struct wlr_allocator *wlr_drm_dumb_allocator_create(int fd) { (void)fd; assert(false); return NULL; }

#define close fake_close
#define fcntl fake_fcntl
#define open fake_open
#define free tracked_free
#define __NetBSD__ 1
/* This file is generated from the supplied, actually patched wlroots source. */
#include "production.inc"
#undef free

int main(int argc, char **argv) {
	assert(argc == 2);
	next_fd = 20; types[10] = DRM_NODE_PRIMARY; types[11] = DRM_NODE_RENDER;
	tables[10] = ++next_table; tables[11] = ++next_table;
	software = strcmp(argv[1], "hardware") != 0;
	bool render_only = strcmp(argv[1], "render-only") == 0;
	no_render = strcmp(argv[1], "no-render") == 0;
	have_reference = strcmp(argv[1], "display-reference") == 0 || strstr(argv[1], "-ref") != NULL;
	fail_dup = strcmp(argv[1], "dup-failure") == 0;
	fail_retry_create = strcmp(argv[1], "create-failure") == 0;
	fail_retry_init = strncmp(argv[1], "init-failure", 12) == 0;
	fail_display = strncmp(argv[1], "display-failure", 15) == 0;
	no_display = strcmp(argv[1], "no-display") == 0;
	fail_open = strcmp(argv[1], "open-failure") == 0;
	fail_auth = strcmp(argv[1], "auth-failure") == 0;
	bool failed = render_only || fail_retry_create || fail_retry_init || fail_display || no_display || fail_open || fail_auth;
	struct wlr_egl *egl = wlr_egl_create_with_drm_fd(render_only ? 11 : 10);
	if (failed) {
		assert(egl == NULL);
	} else {
		assert(egl);
		assert(types[gbm_device_get_fd(egl->gbm_device)] == (software ? DRM_NODE_PRIMARY : DRM_NODE_RENDER));
		assert(tables[gbm_device_get_fd(egl->gbm_device)] != tables[10]);
		int fd = wlr_egl_dup_drm_fd(egl);
		if (fail_dup) {
			assert(fd < 0);
			wlr_egl_destroy(egl);
			goto verify;
		}
		assert(fd >= 0 && types[fd] == (software ? DRM_NODE_PRIMARY : DRM_NODE_RENDER));
		fake_close(fd);
		assert(device_queries == (software ? 0 : 1));
		struct wlr_backend backend = { WLR_BUFFER_CAP_DMABUF };
		struct wlr_renderer renderer = { WLR_BUFFER_CAP_DMABUF, egl };
		struct wlr_allocator *alloc = wlr_allocator_autocreate(&backend, &renderer);
		assert(alloc);
		assert(types[alloc->fd] == (software ? DRM_NODE_PRIMARY : DRM_NODE_RENDER));
		assert(tables[alloc->fd] != tables[gbm_device_get_fd(egl->gbm_device)]);
		assert(tables[alloc->fd] != tables[10]);
		fake_close(alloc->fd);
		wlr_egl_destroy(egl);
	}
verify:
	fprintf(stderr, "remaining formats=%d initialized_displays=%d\n", formats, live_displays);
	assert(formats == 0);
	if (failed) assert(live_displays == 0);
	assert(names == 0 && objects == 0 && devices == 0 && contexts == 0 && opened == closed);
	assert(types[10] == DRM_NODE_PRIMARY && types[11] == DRM_NODE_RENDER);
	if (software && !no_render) assert(strncmp(cleanup, "CTBFE", 5) == 0);
	if (!software || no_render) assert(creates == 1 && inits == 1);
	printf("PASS: %s; %d opens/%d closes, all owned objects released, caller FDs retained\n", argv[1], opened, closed);
	return 0;
}
