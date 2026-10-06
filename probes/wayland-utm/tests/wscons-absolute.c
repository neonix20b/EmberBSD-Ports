/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 EmberBSD contributors. */
/* Origin: EmberBSD, AI-assisted. Exercise real wscons dispatch and getters. */
#include "config.h"
#include <sys/types.h>
#include <sys/ioctl.h>
#include <dev/wscons/wsconsio.h>
#include <assert.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <unistd.h>

static int input_fd;
static int calibration;
int wscons_test_ioctl(int, unsigned long, ...);
#define ioctl wscons_test_ioctl
#include "wscons.c"
#undef ioctl

int
wscons_test_ioctl(int fd, unsigned long request, ...)
{
	va_list ap;
	struct wsmouse_calibcoords *bounds;

	assert(fd >= 0 && request == WSMOUSEIO_GCALIBCOORDS);
	if (calibration == 0) {
		errno = ENOTTY;
		return -1;
	}
	va_start(ap, request);
	bounds = va_arg(ap, struct wsmouse_calibcoords *);
	*bounds = (struct wsmouse_calibcoords) {
		.minx = 100, .maxx = 1100, .miny = -200, .maxy = 1800,
		.samplelen = WSMOUSE_CALIBCOORDS_RESET
	};
	if (calibration == 2)
		bounds->maxx = bounds->minx;
	va_end(ap);
	return 0;
}

static int
open_input(const char *path, int flags, void *data)
{
	(void)path;
	(void)flags;
	(void)data;
	return dup(input_fd);
}

static void
close_input(int fd, void *data)
{
	(void)data;
	close(fd);
}

static void
dispatch(struct libinput_device *device, int fd, int type, int value)
{
	struct wscons_event event = { .type = type, .value = value,
	    .time = { .tv_sec = 1 } };

	assert(write(fd, &event, sizeof(event)) == sizeof(event));
	wscons_device_dispatch(device);
}

static void
check_point(struct libinput *input, double x, double y)
{
	struct libinput_event *event = libinput_get_event(input);
	struct libinput_event_pointer *pointer;

	assert(event && libinput_event_get_type(event) ==
	    LIBINPUT_EVENT_POINTER_MOTION_ABSOLUTE);
	pointer = libinput_event_get_pointer_event(event);
	assert(libinput_event_pointer_get_absolute_x(pointer) == x);
	assert(libinput_event_pointer_get_absolute_y(pointer) == y);
	assert(libinput_event_pointer_get_absolute_x_transformed(pointer, 1000) == x);
	assert(libinput_event_pointer_get_absolute_y_transformed(pointer, 1000) == y / 2);
	libinput_event_destroy(event);
	assert(libinput_get_event(input) == NULL);
}

int
main(void)
{
	const struct libinput_interface interface = {
		.open_restricted = open_input, .close_restricted = close_input
	};
	struct libinput *input;
	struct libinput_device *device;
	struct libinput_event *event;
	struct wscons_event batch[] = {
		{ .type = WSCONS_EVENT_MOUSE_ABSOLUTE_X, .value = 600 },
		{ .type = WSCONS_EVENT_MOUSE_ABSOLUTE_Y, .value = 800 },
		{ .type = WSCONS_EVENT_MOUSE_DOWN, .value = 0 }
	};
	struct udev *udev = udev_new();
	int fds[2];

	assert(udev && pipe(fds) == 0);
	input_fd = fds[0];
	input = libinput_udev_create_context(&interface, NULL, udev);
	assert(input);
	calibration = 1;
	device = libinput_path_add_device(input, "/dev/wsmouse0");
	assert(device);
	/* Axes in one read are combined before the following button. */
	assert(write(fds[1], batch, sizeof(batch)) == sizeof(batch));
	wscons_device_dispatch(device);
	event = libinput_get_event(input);
	assert(event && libinput_event_get_type(event) == LIBINPUT_EVENT_POINTER_MOTION_ABSOLUTE);
	assert(libinput_event_pointer_get_absolute_x_transformed(
	    libinput_event_get_pointer_event(event), 1000) == 500);
	assert(libinput_event_pointer_get_absolute_y_transformed(
	    libinput_event_get_pointer_event(event), 1000) == 500);
	libinput_event_destroy(event);
	event = libinput_get_event(input);
	assert(event && libinput_event_get_type(event) == LIBINPUT_EVENT_POINTER_BUTTON);
	libinput_event_destroy(event);
	/* Single-axis reads retain the other coordinate; endpoints scale exactly. */
	dispatch(device, fds[1], WSCONS_EVENT_MOUSE_ABSOLUTE_X, 100);
	check_point(input, 0, 1000);
	dispatch(device, fds[1], WSCONS_EVENT_MOUSE_ABSOLUTE_Y, -200);
	check_point(input, 0, 0);
	dispatch(device, fds[1], WSCONS_EVENT_MOUSE_ABSOLUTE_X, 1100);
	check_point(input, 1000, 0);
	dispatch(device, fds[1], WSCONS_EVENT_MOUSE_ABSOLUTE_Y, 1800);
	check_point(input, 1000, 2000);
	libinput_path_remove_device(device);
	/* Unsupported or invalid calibration preserves relative mouse operation. */
	for (calibration = 0; calibration <= 2; calibration += 2) {
		device = libinput_path_add_device(input, "/dev/wsmouse1");
		assert(device);
		dispatch(device, fds[1], WSCONS_EVENT_MOUSE_ABSOLUTE_X, 600);
		assert(libinput_get_event(input) == NULL);
		dispatch(device, fds[1], WSCONS_EVENT_MOUSE_DELTA_X, 10);
		event = libinput_get_event(input);
		assert(event && libinput_event_get_type(event) == LIBINPUT_EVENT_POINTER_MOTION);
		libinput_event_destroy(event);
		libinput_path_remove_device(device);
	}
	libinput_unref(input);
	udev_unref(udev);
	close(fds[0]);
	close(fds[1]);
	puts("PASS: absolute dispatch, button ordering, getters, endpoints and relative fallback");
	return 0;
}
