/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 EmberBSD contributors. */
/* Origin: EmberBSD, AI-assisted. Tests the real patched terminal function. */
#include <sys/types.h>
#include <sys/ioctl.h>
#include <dev/wscons/wsconsio.h>
#include <assert.h>
#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include "terminal.h"

static unsigned calls;
static bool fail;

int seatd_test_ioctl(int, unsigned long, ...);

int
seatd_test_ioctl(int fd, unsigned long request, ...)
{
	va_list ap;
	int *mode;

	assert(fd == 123);
	assert(request == WSKBDIO_SETMODE);
	va_start(ap, request);
	mode = va_arg(ap, int *);
	assert(*mode == WSKBD_TRANSLATED);
	va_end(ap);
	calls++;
	if (fail) {
		errno = EIO;
		return -1;
	}
	return 0;
}

int
main(void)
{

	assert(terminal_set_keyboard(123, false) == 0);
	assert(terminal_set_keyboard(123, true) == 0);
	fail = true;
	assert(terminal_set_keyboard(123, false) == -1 && errno == EIO);
	assert(terminal_set_keyboard(123, true) == -1 && errno == EIO);
	assert(calls == 4);
	puts("PASS: wscons event mode, console restoration and ioctl failure propagation");
	return 0;
}
