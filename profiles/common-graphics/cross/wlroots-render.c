/* SPDX-License-Identifier: BSD-2-Clause
 * Origin: EmberBSD (AI-assisted). Real wlroots GLES2/GBM headless consumer.
 * Uses wlroots 0.20 public unstable interfaces; no replacement renderer.
 */
#include <sys/stat.h>
#include <sys/wait.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <drm_fourcc.h>
#include <linux/input-event-codes.h>
#include <wayland-server-core.h>
#include <wlr/backend.h>
#include <wlr/backend/headless.h>
#include <wlr/render/allocator.h>
#include <wlr/render/drm_format_set.h>
#include <wlr/render/egl.h>
#include <wlr/render/gles2.h>
#include <wlr/render/pass.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_buffer.h>
#include <wlr/types/wlr_output.h>
#include <wlr/util/log.h>
#include <xkbcommon/xkbcommon.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <inttypes.h>
#include <link_elf.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SIDE 32
#define REQUIRE(test, message) do { \
	if (!(test)) { failure = (message); goto done; } \
} while (0)

static int
loaded_library(struct dl_phdr_info *info, size_t size, void *argument)
{
	const char *executable = argument;
	const char *name = info->dlpi_name;

	(void)size;
	if (name[0] == '\0' || strcmp(name, executable) == 0)
		return 0;
	if (strncmp(name, "/usr/pkg/", 9) != 0 &&
	    strncmp(name, "/usr/lib/", 9) != 0 &&
	    strncmp(name, "/lib/", 5) != 0 &&
	    strcmp(name, "/libexec/ld.elf_so") != 0 &&
	    strcmp(name, "/usr/libexec/ld.elf_so") != 0) {
		fprintf(stderr, "FAIL: unexpected loaded library: %s\n", name);
		return 1;
	}
	printf("LOADED: %s\n", name);
	return 0;
}

struct presentation {
	struct wl_listener listener;
	bool seen;
};

static void
presented(struct wl_listener *listener, void *data)
{
	struct presentation *presentation = wl_container_of(listener, presentation, listener);
	const struct wlr_output_event_present *event = data;

	presentation->seen = event->presented;
}

static bool
keyboard(void)
{
	struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	struct xkb_rule_names names = { .rules = "evdev", .model = "pc105", .layout = "us" };
	struct xkb_keymap *keymap = NULL;
	struct xkb_state *state = NULL;
	char text[8];
	bool ok = false;

	if (context == NULL)
		goto done;
	keymap = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
	if (keymap == NULL || (state = xkb_state_new(keymap)) == NULL)
		goto done;
	if (xkb_state_key_get_utf8(state, KEY_A + 8, text, sizeof(text)) != 1 || strcmp(text, "a") != 0)
		goto done;
	xkb_state_update_key(state, KEY_LEFTSHIFT + 8, XKB_KEY_DOWN);
	if (xkb_state_key_get_utf8(state, KEY_A + 8, text, sizeof(text)) != 1 || strcmp(text, "A") != 0)
		goto done;
	ok = true;
done:
	xkb_state_unref(state);
	xkb_keymap_unref(keymap);
	xkb_context_unref(context);
	puts(ok ? "PASS: installed XKB data maps A and Shift+A" : "FAIL: installed XKB keymap");
	return ok;
}

static bool
cycle(const char *node, const char *executable, unsigned number, bool drop_privileges)
{
	struct wl_display *display = NULL;
	struct wlr_backend *backend = NULL;
	struct wlr_renderer *renderer = NULL;
	struct wlr_allocator *allocator = NULL;
	struct wlr_buffer *buffer = NULL;
	struct wlr_texture *source = NULL, *readback = NULL;
	struct wlr_render_pass *pass = NULL;
	struct wlr_output *output = NULL;
	drmModeRes *resources = NULL;
	struct wlr_egl *egl;
	struct wlr_output_state state;
	struct wlr_dmabuf_attributes dmabuf;
	struct presentation presentation = {0};
	struct stat st;
	uint64_t linear = DRM_FORMAT_MOD_LINEAR;
	struct wlr_drm_format format = { .format = DRM_FORMAT_ARGB8888,
	    .len = 1, .capacity = 1, .modifiers = &linear };
	const uint32_t blue[4] = { 0xff0000ff, 0xff0000ff, 0xff0000ff, 0xff0000ff };
	uint32_t pixels[SIDE * SIDE];
	uint32_t caller_handle = 0, renderer_handle = 0, framebuffer = 0;
	uint64_t map_offset;
	const char *failure = NULL, *gl_renderer;
	bool state_initialized = false, listening = false, renderer_handle_invalid = false;
	int fd = -1;
	unsigned x, y;

	fd = open(node, O_RDWR | O_CLOEXEC);
	REQUIRE(fd >= 0 && fstat(fd, &st) == 0 && S_ISCHR(st.st_mode), "real DRM device");
	if (drop_privileges) {
		REQUIRE(geteuid() == 0, "privilege-drop harness starts with root master opener");
		REQUIRE(drmIsMaster(fd), "opened caller FD is DRM master");
		REQUIRE(setgroups(0, NULL) == 0 && setgid(65534) == 0 && setuid(65534) == 0,
		    "drop supplementary groups, GID and UID before renderer creation");
		REQUIRE(getuid() == 65534 && geteuid() == 65534 && getgid() == 65534 &&
		    getegid() == 65534 && getgroups(0, NULL) == 0, "verify unprivileged renderer process");
		printf("Cycle %u: UID/EUID/GID/EGID=65534, no supplementary groups; retained master=%d\n",
		    number, drmIsMaster(fd));
	}
	resources = drmModeGetResources(fd);
	REQUIRE(resources != NULL, "actual KMS framebuffer size limits");
	printf("KMS dimensions: %dx%d; supported %ux%u through %ux%u\n", SIDE, SIDE,
	    resources->min_width, resources->min_height, resources->max_width, resources->max_height);
	REQUIRE(SIDE >= resources->min_width && SIDE >= resources->min_height &&
	    SIDE <= resources->max_width && SIDE <= resources->max_height, "test size within actual KMS limits");
	display = wl_display_create();
	REQUIRE(display != NULL, "Wayland display");
	backend = wlr_headless_backend_create(wl_display_get_event_loop(display));
	REQUIRE(backend != NULL && wlr_backend_is_headless(backend), "headless backend");
	renderer = wlr_gles2_renderer_create_with_drm_fd(fd);
	REQUIRE(renderer != NULL && wlr_renderer_is_gles2(renderer), "actual wlroots GLES2 renderer");
	REQUIRE(renderer->render_buffer_caps & WLR_BUFFER_CAP_DMABUF, "GLES2 DMA-BUF capability");
	egl = wlr_gles2_renderer_get_egl(renderer);
	REQUIRE(eglMakeCurrent(wlr_egl_get_display(egl), EGL_NO_SURFACE, EGL_NO_SURFACE,
	    wlr_egl_get_context(egl)), "query actual GLES renderer");
	gl_renderer = (const char *)glGetString(GL_RENDERER);
	REQUIRE(gl_renderer != NULL && strstr(gl_renderer, "llvmpipe") != NULL, "explicit CPU llvmpipe renderer");
	printf("Cycle %u: wlroots GLES2 renderer: %s\n", number, gl_renderer);
	REQUIRE(eglMakeCurrent(wlr_egl_get_display(egl), EGL_NO_SURFACE, EGL_NO_SURFACE,
	    EGL_NO_CONTEXT), "release query context");
	allocator = wlr_allocator_autocreate(backend, renderer);
	REQUIRE(allocator != NULL && (allocator->buffer_caps & WLR_BUFFER_CAP_DMABUF), "real DMA-BUF allocator");
	buffer = wlr_allocator_create_buffer(allocator, SIDE, SIDE, &format);
	REQUIRE(buffer != NULL && wlr_buffer_get_dmabuf(buffer, &dmabuf), "allocate wlroots DMA-BUF");
	REQUIRE(dmabuf.n_planes == 1 && dmabuf.modifier == linear && dmabuf.format == format.format &&
	    dmabuf.fd[0] >= 0, "actual linear ARGB8888 DMA-BUF");
	printf("BO: modifier=%#" PRIx64 " stride=%" PRIu32 " offset=%" PRIu32 "\n",
	    dmabuf.modifier, dmabuf.stride[0], dmabuf.offset[0]);
	source = wlr_texture_from_pixels(renderer, DRM_FORMAT_ARGB8888, 8, 2, 2, blue);
	REQUIRE(source != NULL && wlr_texture_is_gles2(source), "actual GLES2 upload texture");
	pass = wlr_renderer_begin_buffer_pass(renderer, buffer, NULL);
	REQUIRE(pass != NULL, "begin wlroots GLES2 buffer pass");
	const struct wlr_render_rect_options background = {
		.box = {0, 0, SIDE, SIDE}, .color = {1, 0, 0, 1}, .blend_mode = WLR_RENDER_BLEND_MODE_NONE };
	const struct wlr_render_rect_options foreground = {
		.box = {4, 4, 8, 8}, .color = {0, 1, 0, 1}, .blend_mode = WLR_RENDER_BLEND_MODE_NONE };
	const struct wlr_render_texture_options texture = {
		.texture = source, .dst_box = {6, 6, 4, 4}, .filter_mode = WLR_SCALE_FILTER_NEAREST,
		.blend_mode = WLR_RENDER_BLEND_MODE_NONE };
	wlr_render_pass_add_rect(pass, &background);
	wlr_render_pass_add_rect(pass, &foreground);
	wlr_render_pass_add_texture(pass, &texture);
	bool submitted = wlr_render_pass_submit(pass);
	pass = NULL;
	REQUIRE(submitted, "submit real GLES2 shader pass");
	/*
	 * Mirror backend/drm/fb.c: import into the caller's GEM table, retain
	 * a KMS framebuffer, then close its temporary import handle. Mesa owns
	 * the renderer's existing import handle; it must survive that close.
	 */
	int renderer_fd = wlr_renderer_get_drm_fd(renderer);
	REQUIRE(renderer_fd >= 0 && drmPrimeFDToHandle(renderer_fd, dmabuf.fd[0],
	    &renderer_handle) == 0, "inspect Mesa renderer GEM import");
	REQUIRE(drmPrimeFDToHandle(fd, dmabuf.fd[0], &caller_handle) == 0,
	    "caller PRIME framebuffer import");
	uint32_t handles[4] = {caller_handle, 0, 0, 0};
	if (drmModeAddFB2(fd, SIDE, SIDE, dmabuf.format, handles,
	    dmabuf.stride, dmabuf.offset, &framebuffer, 0) != 0) {
		fprintf(stderr, "drmModeAddFB2 %dx%d stride=%" PRIu32 " offset=%" PRIu32 ": %s (errno=%d)\n",
		    SIDE, SIDE, dmabuf.stride[0], dmabuf.offset[0], strerror(errno), errno);
		failure = "actual KMS framebuffer creation without scanout";
		goto done;
	}
	REQUIRE(drmCloseBufferHandle(fd, caller_handle) == 0, "close caller framebuffer import handle");
	caller_handle = 0;
	if (drmModeMapDumbBuffer(renderer_fd, renderer_handle, &map_offset) != 0) {
		fprintf(stderr, "renderer MAP_DUMB handle=%" PRIu32 ": %s (errno=%d)\n",
		    renderer_handle, strerror(errno), errno);
		renderer_handle_invalid = true;
		failure = "renderer MAP_DUMB survives caller framebuffer GEM_CLOSE";
		goto done;
	}
	printf("PASS: caller KMS framebuffer import/GEM_CLOSE preserves renderer MAP_DUMB\n");
	readback = wlr_texture_from_buffer(renderer, buffer);
	REQUIRE(readback != NULL && wlr_texture_is_gles2(readback), "import rendered buffer for readback");
	const struct wlr_texture_read_pixels_options read_options = {
		.data = pixels, .format = DRM_FORMAT_ARGB8888, .stride = SIDE * 4 };
	REQUIRE(wlr_texture_read_pixels(readback, &read_options), "wlroots GLES2 pixel readback");
	for (y = 0; y < SIDE; y++) {
		for (x = 0; x < SIDE; x++) {
			uint32_t expected = 0xffff0000;
			if (x >= 4 && x < 12 && y >= 4 && y < 12)
				expected = 0xff00ff00;
			if (x >= 6 && x < 10 && y >= 6 && y < 10)
				expected = 0xff0000ff;
			if (pixels[y * SIDE + x] != expected) {
				fprintf(stderr, "Pixel %u,%u: %#x != %#x\n", x, y, pixels[y * SIDE + x], expected);
				failure = "all 1024 renderer pixels";
				goto done;
			}
		}
	}
	output = wlr_headless_add_output(backend, SIDE, SIDE);
	REQUIRE(output != NULL && wlr_output_is_headless(output) &&
	    wlr_output_init_render(output, allocator, renderer), "headless GLES2 output");
	presentation.listener.notify = presented;
	wl_signal_add(&output->events.present, &presentation.listener);
	listening = true;
	REQUIRE(wlr_backend_start(backend), "start headless backend");
	wlr_output_state_init(&state);
	state_initialized = true;
	wlr_output_state_set_enabled(&state, true);
	wlr_output_state_set_buffer(&state, buffer);
	REQUIRE(wlr_output_commit_state(output, &state), "commit rendered headless output buffer");
	REQUIRE(wl_event_loop_dispatch(wl_display_get_event_loop(display), 0) == 0 &&
	    presentation.seen, "actual headless presentation event");
	REQUIRE(dl_iterate_phdr(loaded_library, (void *)executable) == 0, "live provider inventory");
done:
	if (failure != NULL)
		fprintf(stderr, "FAIL cycle %u: %s\n", number, failure);
	if (renderer_handle_invalid) {
		/*
		 * This negative oracle has proved the renderer's GEM table corrupt.
		 * Calling Mesa destructors can dereference the invalid mapping. Let
		 * process teardown reclaim kernel resources; never report cleanup PASS.
		 */
		fputs("FAIL: damaged renderer; process teardown instead of unsafe Mesa destruction\n", stderr);
		fflush(NULL);
		_Exit(EXIT_FAILURE);
	}
	if (pass != NULL)
		(void)wlr_render_pass_submit(pass);
	if (state_initialized)
		wlr_output_state_finish(&state);
	if (listening)
		wl_list_remove(&presentation.listener.link);
	if (output != NULL)
		wlr_output_destroy(output);
	if (framebuffer != 0)
		(void)drmModeRmFB(fd, framebuffer);
	if (readback != NULL)
		wlr_texture_destroy(readback);
	if (source != NULL)
		wlr_texture_destroy(source);
	if (buffer != NULL)
		wlr_buffer_drop(buffer);
	if (allocator != NULL)
		wlr_allocator_destroy(allocator);
	if (renderer != NULL)
		wlr_renderer_destroy(renderer);
	/* On a pre-oracle error this may still alias Mesa's handle in a broken provider. */
	if (caller_handle != 0)
		(void)drmCloseBufferHandle(fd, caller_handle);
	if (backend != NULL)
		wlr_backend_destroy(backend);
	if (display != NULL)
		wl_display_destroy(display);
	if (resources != NULL)
		drmModeFreeResources(resources);
	if (fd >= 0)
		close(fd);
	if (failure != NULL)
		return false;
	printf("PASS cycle %u: GLES2 rectangles/texture, 1024 pixels, headless commit and cleanup\n", number);
	return true;
}

int
main(int argc, char **argv)
{
	const char *software = getenv("LIBGL_ALWAYS_SOFTWARE");
	const char *allow = getenv("WLR_RENDERER_ALLOW_SOFTWARE");
	bool drop_privileges = argc == 3 && strcmp(argv[2], "--drop-privileges") == 0;

	setvbuf(stdout, NULL, _IOLBF, 0);
	if ((argc != 2 && !drop_privileges) || strncmp(argv[1], "/dev/dri/", 9) != 0 || strstr(argv[1], "..") != NULL ||
	    software == NULL || strcmp(software, "1") != 0 || allow == NULL || strcmp(allow, "1") != 0) {
		fprintf(stderr, "Usage: LIBGL_ALWAYS_SOFTWARE=1 WLR_RENDERER_ALLOW_SOFTWARE=1 wlroots-render /dev/dri/DEVICE [--drop-privileges]\n");
		return 2;
	}
	wlr_log_init(WLR_DEBUG, NULL);
	if (!keyboard())
		return 1;
	for (unsigned i = 1; i <= 4; i++) {
		if (drop_privileges) {
			pid_t child = fork();
			if (child < 0) {
				perror("fork privilege-drop cycle");
				return 1;
			}
			if (child == 0)
				exit(cycle(argv[1], argv[0], i, true) ? 0 : 1);
			int status;
			if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
				fprintf(stderr, "FAIL: unprivileged cycle %u\n", i);
				return 1;
			}
		} else if (!cycle(argv[1], argv[0], i, false)) {
			return 1;
		}
	}
	puts("PASS: wlroots GLES2 CPU consumer; no DRM scanout, physical input or visible compositor claim");
	return 0;
}
