/* Origin: EmberBSD; AI-assisted production-helper DSO regression.
 * SPDX-License-Identifier: BSD-2-Clause
 */
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <pthread.h>
#include "util/u_atexit.h"

extern "C" void record_event(int);
static pthread_t worker;
static bool queue_stopped, object_destroyed;

static void *work(void *) { return nullptr; }
static void last_cleanup()
{
	assert(queue_stopped && object_destroyed);
	record_event(DSO_ID * 10 + 1);
}
struct Owner {
	~Owner()
	{
		if (!queue_stopped) {
			std::fputs("missing queue cleanup before C++ owner destruction\n", stderr);
			std::abort();
		}
		object_destroyed = true;
		record_event(DSO_ID * 10 + 2);
	}
};
static void stop_queue()
{
	assert(!queue_stopped && !object_destroyed);
	assert(pthread_join(worker, nullptr) == 0);
	queue_stopped = true;
	record_event(DSO_ID * 10 + 3);
}
static void first_cleanup()
{
	assert(!queue_stopped && !object_destroyed);
	record_event(DSO_ID * 10 + 4);
}
extern "C" __attribute__((visibility("default"))) void start_callbacks()
{
	assert(util_atexit(last_cleanup) == 0);
	static Owner owner;
	(void)owner;
	assert(pthread_create(&worker, nullptr, work, nullptr) == 0);
	assert(util_atexit(stop_queue) == 0);
	assert(util_atexit(first_cleanup) == 0);
}
