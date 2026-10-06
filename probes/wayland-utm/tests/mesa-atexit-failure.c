/* Origin: EmberBSD; AI-assisted production-helper fault regression.
 * SPDX-License-Identifier: BSD-2-Clause
 */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned allocations, frees, registrations, calls;
static int fail_allocation, registration_result;
static void (*saved_callback)(void *);
static void *saved_data, *saved_owner;
void *test_dso_handle;

static void *
test_malloc(size_t size)
{
	if (fail_allocation)
		return NULL;
	void *p = malloc(size);
	assert(p != NULL);
	allocations++;
	return p;
}

static void
test_free(void *p)
{
	assert(p != NULL);
	frees++;
	free(p);
}

static int
test_cxa_atexit(void (*func)(void *), void *arg, void *owner)
{
	registrations++;
	saved_callback = func;
	saved_data = arg;
	saved_owner = owner;
	return registration_result;
}

/* The actual patched translation unit; replace only allocation/ABI boundaries.
 * Include system headers first so the host can exercise the NetBSD branch.
 */
#ifndef __NetBSD__
#define __NetBSD__ 1
#endif
#define malloc test_malloc
#define free test_free
#define __cxa_atexit test_cxa_atexit
#define __dso_handle test_dso_handle
#include "util/u_atexit.c"
#undef malloc
#undef free

static void
callback(void)
{
	/* The wrapper must already be released when user cleanup runs. */
	assert(allocations == frees);
	calls++;
}

int
main(void)
{
	fail_allocation = 1;
	assert(util_atexit(callback) != 0);
	assert(allocations == 0 && registrations == 0 && frees == 0);
	fail_allocation = 0;
	registration_result = 7;
	assert(util_atexit(callback) == 7);
	assert(allocations == 1 && frees == 1 && calls == 0);
	registration_result = 0;
	assert(util_atexit(callback) == 0);
	assert(allocations == 2 && frees == 1 && registrations == 2);
	assert(saved_owner == &test_dso_handle);
	saved_callback(saved_data);
	assert(calls == 1 && allocations == frees);
	puts("allocation/registration failure and owner contract: PASS");
	return 0;
}
