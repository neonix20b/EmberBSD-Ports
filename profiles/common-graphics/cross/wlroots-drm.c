/* SPDX-License-Identifier: BSD-2-Clause
 * Origin: EmberBSD (AI-assisted). Actual wlroots DRM/session/GLES2 consumer.
 * Based on the public wlroots 0.20 example/API, with bounded pixel/present checks.
 */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <drm_fourcc.h>
#include <wayland-server-core.h>
#include <wlr/backend.h>
#include <wlr/backend/drm.h>
#include <wlr/backend/libinput.h>
#include <wlr/backend/multi.h>
#include <wlr/backend/session.h>
#include <wlr/render/allocator.h>
#include <wlr/render/egl.h>
#include <wlr/render/gles2.h>
#include <wlr/render/pass.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_buffer.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_output.h>
#include <wlr/util/log.h>
#include <link_elf.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SIDE 32
struct test {
	struct wl_display *display;
	struct wlr_backend *backend;
	struct wlr_session *session;
	struct wlr_renderer *renderer;
	struct wlr_allocator *allocator;
	struct wlr_output *output;
	struct wl_listener new_output, new_input, frame, present, destroy;
	const char *executable;
	const char *failure;
	unsigned presented, inputs, drm_backends, input_backends;
	uint32_t pending_seq;
	bool pending;
};

static void
fail(struct test *test, const char *message)
{
	if (test->failure == NULL) {
		test->failure = message;
		fprintf(stderr, "FAIL: %s\n", message);
	}
	wl_display_terminate(test->display);
}

static int
loaded_library(struct dl_phdr_info *info, size_t size, void *argument)
{
	const char *name = info->dlpi_name;
	const char *executable = argument;

	(void)size;
	if (*name == '\0' || strcmp(name, executable) == 0)
		return 0;
	if (strncmp(name, "/usr/pkg/", 9) != 0 &&
	    strncmp(name, "/usr/lib/", 9) != 0 && strncmp(name, "/lib/", 5) != 0 &&
	    strcmp(name, "/libexec/ld.elf_so") != 0 &&
	    strcmp(name, "/usr/libexec/ld.elf_so") != 0) {
		fprintf(stderr, "FAIL: unexpected loaded library: %s\n", name);
		return 1;
	}
	printf("LOADED: %s\n", name);
	return 0;
}

static bool
pixels(struct test *test, struct wlr_buffer *buffer)
{
	struct wlr_texture *texture = wlr_texture_from_buffer(test->renderer, buffer);
	uint32_t data[SIDE * SIDE];
	struct wlr_texture_read_pixels_options options = {
		.data = data, .format = DRM_FORMAT_ARGB8888,
		.stride = SIDE * sizeof(uint32_t),
		.src_box = { .width = SIDE, .height = SIDE }
	};
	unsigned x, y;
	bool ok;

	if (texture == NULL)
		return false;
	ok = wlr_texture_read_pixels(texture, &options);
	wlr_texture_destroy(texture);
	if (!ok)
		return false;
	for (y = 0; y < SIDE; y++) {
		for (x = 0; x < SIDE; x++) {
			uint32_t expected = 0xffff0000;
			if (x >= 8 && x < 24 && y >= 8 && y < 24)
				expected = 0xff00ff00;
			if (data[y * SIDE + x] != expected) {
				fprintf(stderr, "Pixel %u,%u: %#x != %#x\n", x, y,
				    data[y * SIDE + x], expected);
				return false;
			}
		}
	}
	return true;
}

static void
frame(struct wl_listener *listener, void *argument)
{
	struct test *test = wl_container_of(listener, test, frame);
	struct wlr_output_state state;
	struct wlr_render_pass *pass;
	bool ok;

	(void)argument;
	if (test->failure != NULL || test->pending || test->presented == 4)
		return;
	wlr_output_state_init(&state);
	pass = wlr_output_begin_render_pass(test->output, &state, NULL);
	if (pass == NULL) {
		wlr_output_state_finish(&state);
		fail(test, "actual DRM output render pass");
		return;
	}
	wlr_render_pass_add_rect(pass, &(struct wlr_render_rect_options) {
		.box = { .width = test->output->width, .height = test->output->height },
		.color = { .r = 1.0f, .a = 1.0f },
	});
	wlr_render_pass_add_rect(pass, &(struct wlr_render_rect_options) {
		.box = { .x = 8, .y = 8, .width = 16, .height = 16 },
		.color = { .g = 1.0f, .a = 1.0f },
	});
	ok = wlr_render_pass_submit(pass);
	if (ok)
		ok = state.buffer != NULL && pixels(test, state.buffer);
	if (ok) {
		ok = wlr_output_commit_state(test->output, &state);
		if (ok) {
			test->pending = true;
			test->pending_seq = test->output->commit_seq;
			printf("COMMIT: seq=%u, real DRM buffer, 1024 GLES2 pixels verified\n",
			    test->pending_seq);
		}
	}
	wlr_output_state_finish(&state);
	if (!ok)
		fail(test, "render/readback/actual DRM commit");
}

static void
present(struct wl_listener *listener, void *argument)
{
	struct test *test = wl_container_of(listener, test, present);
	const struct wlr_output_event_present *event = argument;

	if (!test->pending || event->commit_seq != test->pending_seq)
		return;
	if (!event->presented) {
		fail(test, "submitted DRM frame was not presented");
		return;
	}
	test->pending = false;
	test->presented++;
	printf("PRESENT: frame=%u seq=%u flags=%#x refresh=%d\n",
	    test->presented, event->commit_seq, event->flags, event->refresh);
	if (test->presented == 4) {
		if (dl_iterate_phdr(loaded_library, (void *)test->executable) != 0)
			fail(test, "live provider inventory");
		wl_display_terminate(test->display);
	} else {
		wlr_output_schedule_frame(test->output);
	}
}

static void
destroy_output(struct wl_listener *listener, void *argument)
{
	struct test *test = wl_container_of(listener, test, destroy);

	(void)argument;
	wl_list_remove(&test->frame.link);
	wl_list_remove(&test->present.link);
	wl_list_remove(&test->destroy.link);
	test->output = NULL;
	if (test->presented != 4 && test->failure == NULL)
		fail(test, "DRM output disappeared before acceptance");
}

static void
new_output(struct wl_listener *listener, void *argument)
{
	struct test *test = wl_container_of(listener, test, new_output);
	struct wlr_output *output = argument;
	struct wlr_output_mode *mode;
	struct wlr_output_state state;
	bool ok;

	if (test->output != NULL)
		return;
	if (!wlr_output_is_drm(output) ||
	    !wlr_output_init_render(output, test->allocator, test->renderer)) {
		fail(test, "real DRM output with GLES2 renderer");
		return;
	}
	mode = wlr_output_preferred_mode(output);
	if (mode == NULL || mode->width < SIDE || mode->height < SIDE) {
		fail(test, "actual connector exposes a suitable preferred mode");
		return;
	}
	test->output = output;
	test->frame.notify = frame;
	test->present.notify = present;
	test->destroy.notify = destroy_output;
	wl_signal_add(&output->events.frame, &test->frame);
	wl_signal_add(&output->events.present, &test->present);
	wl_signal_add(&output->events.destroy, &test->destroy);
	wlr_output_state_init(&state);
	wlr_output_state_set_enabled(&state, true);
	wlr_output_state_set_mode(&state, mode);
	ok = wlr_output_commit_state(output, &state);
	wlr_output_state_finish(&state);
	if (!ok) {
		fail(test, "real DRM modeset");
		return;
	}
	printf("OUTPUT: %s %dx%d@%d, actual DRM backend\n", output->name,
	    mode->width, mode->height, mode->refresh);
	wlr_output_schedule_frame(output);
}

static void
new_input(struct wl_listener *listener, void *argument)
{
	struct test *test = wl_container_of(listener, test, new_input);
	const struct wlr_input_device *input = argument;

	test->inputs++;
	printf("INPUT: type=%d name=%s (enumeration only)\n", input->type, input->name);
}

static void
backend_kind(struct wlr_backend *backend, void *argument)
{
	struct test *test = argument;

	test->drm_backends += wlr_backend_is_drm(backend);
	test->input_backends += wlr_backend_is_libinput(backend);
}

static int
deadline(void *argument)
{
	fail(argument, "30-second DRM presentation deadline");
	return 0;
}

/* Select an explicit renderer policy before creating a display or session. */
static const char *
expected_renderer(int argc, char **argv)
{
	static const char *const forbidden[] = {
		"LD_LIBRARY_PATH", "LD_PRELOAD", "LIBGL_DRIVERS_PATH",
		"GBM_BACKENDS_PATH", "MESA_LOADER_DRIVER_OVERRIDE", "GALLIUM_DRIVER",
		"WLR_RENDERER_FORCE_SOFTWARE", "WLR_RENDERER", "WLR_RENDER_DRM_DEVICE"
	};
	const char *expected, *software, *allowed;
	size_t i;

	if (argc != 1 && argc != 2)
		return NULL;
	expected = argc == 1 ? "llvmpipe" : argv[1];
	if (strcmp(expected, "llvmpipe") != 0 && strcmp(expected, "virgl") != 0)
		return NULL;
	for (i = 0; i < sizeof(forbidden) / sizeof(forbidden[0]); i++) {
		if (getenv(forbidden[i]) != NULL)
			return NULL;
	}
	software = getenv("LIBGL_ALWAYS_SOFTWARE");
	allowed = getenv("WLR_RENDERER_ALLOW_SOFTWARE");
	if (strcmp(expected, "llvmpipe") == 0) {
		if (software == NULL || strcmp(software, "1") != 0 ||
		    allowed == NULL || strcmp(allowed, "1") != 0)
			return NULL;
	} else if (software != NULL || allowed != NULL) {
		return NULL;
	}
	return expected;
}

static bool
renderer_matches(const char *expected, const char *actual)
{
	size_t length = strlen(expected);

	return actual != NULL && strncmp(actual, expected, length) == 0 &&
	    (actual[length] == '\0' || actual[length] == ' ');
}

int
main(int argc, char **argv)
{
	struct test test = { .executable = argv[0] };
	struct wl_event_source *timer = NULL;
	struct wlr_egl *egl;
	const char *renderer, *expected;
	bool listeners = false;
	int result = EXIT_FAILURE;

	setvbuf(stdout, NULL, _IOLBF, 0);
	expected = expected_renderer(argc, argv);
	if (expected == NULL) {
		fprintf(stderr, "Usage: wlroots-drm [llvmpipe|virgl] with matching renderer environment\n");
		return EXIT_FAILURE;
	}
	wlr_log_init(WLR_DEBUG, NULL);
	test.display = wl_display_create();
	if (test.display == NULL)
		return EXIT_FAILURE;
	test.backend = wlr_backend_autocreate(wl_display_get_event_loop(test.display), &test.session);
	if (test.backend == NULL || test.session == NULL) {
		fail(&test, "actual DRM/libinput/libseat session creation");
		goto done;
	}
	wlr_multi_for_each_backend(test.backend, backend_kind, &test);
	if (test.drm_backends == 0 || test.input_backends == 0 || !test.session->active) {
		fail(&test, "DRM and libinput backends plus active libseat session");
		goto done;
	}
	test.renderer = wlr_renderer_autocreate(test.backend);
	if (test.renderer == NULL || !wlr_renderer_is_gles2(test.renderer)) {
		fail(&test, "actual GLES2 renderer");
		goto done;
	}
	egl = wlr_gles2_renderer_get_egl(test.renderer);
	if (!eglMakeCurrent(wlr_egl_get_display(egl), EGL_NO_SURFACE, EGL_NO_SURFACE,
	    wlr_egl_get_context(egl))) {
		fail(&test, "query actual GLES renderer");
		goto done;
	}
	renderer = (const char *)glGetString(GL_RENDERER);
	if (!renderer_matches(expected, renderer))
		fail(&test, "actual renderer differs from explicit expected renderer");
	printf("RENDERER: %s\n", renderer == NULL ? "(missing)" : renderer);
	if (!eglMakeCurrent(wlr_egl_get_display(egl), EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT))
		fail(&test, "release query context");
	if (test.failure != NULL)
		goto done;
	test.allocator = wlr_allocator_autocreate(test.backend, test.renderer);
	if (test.allocator == NULL) {
		fail(&test, "real output allocator");
		goto done;
	}
	test.new_output.notify = new_output;
	test.new_input.notify = new_input;
	wl_signal_add(&test.backend->events.new_output, &test.new_output);
	wl_signal_add(&test.backend->events.new_input, &test.new_input);
	listeners = true;
	timer = wl_event_loop_add_timer(wl_display_get_event_loop(test.display), deadline, &test);
	if (timer == NULL || wl_event_source_timer_update(timer, 30000) < 0 ||
	    !wlr_backend_start(test.backend)) {
		fail(&test, "start actual backends and deadline");
		goto done;
	}
	if (test.failure == NULL)
		wl_display_run(test.display);
	if (test.failure == NULL && test.presented == 4)
		result = EXIT_SUCCESS;
done:
	if (timer != NULL)
		wl_event_source_remove(timer);
	if (listeners) {
		wl_list_remove(&test.new_output.link);
		wl_list_remove(&test.new_input.link);
	}
	if (test.backend != NULL)
		wlr_backend_destroy(test.backend);
	if (test.allocator != NULL)
		wlr_allocator_destroy(test.allocator);
	if (test.renderer != NULL)
		wlr_renderer_destroy(test.renderer);
	if (test.session != NULL)
		wlr_session_destroy(test.session);
	wl_display_destroy(test.display);
	if (result == EXIT_SUCCESS)
		printf("PASS: four actual DRM presentations, GLES2 pixels, libseat session; %u input devices enumerated; cleanup\n", test.inputs);
	return result;
}
