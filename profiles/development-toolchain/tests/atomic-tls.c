/* SPDX-License-Identifier: BSD-2-Clause */
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>

static atomic_uint_fast64_t count;
static _Thread_local unsigned int local;

static void *
worker(void *argument)
{

	(void)argument;
	assert(local == 0);
	for (unsigned int i = 0; i < 10000; i++) {
		local++;
		atomic_fetch_add_explicit(&count, 1, memory_order_relaxed);
	}
	assert(local == 10000);
	return NULL;
}

int
main(void)
{
	pthread_t first, second;

	local = 7;
	assert(pthread_create(&first, NULL, worker, NULL) == 0);
	assert(pthread_create(&second, NULL, worker, NULL) == 0);
	assert(pthread_join(first, NULL) == 0);
	assert(pthread_join(second, NULL) == 0);
	assert(atomic_load(&count) == 20000);
	assert(local == 7);
	return 0;
}
