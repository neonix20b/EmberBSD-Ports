#include <sys/types.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t ready = PTHREAD_COND_INITIALIZER;
static uint32_t (*check)(void);
static int released, entered;
static uint32_t result;

static void *
worker(void *unused)
{
	(void)unused;
	if (pthread_mutex_lock(&lock) != 0)
		abort();
	entered = 1;
	if (pthread_cond_broadcast(&ready) != 0)
		abort();
	while (!released) {
		if (pthread_cond_wait(&ready, &lock) != 0)
			abort();
	}
	if (pthread_mutex_unlock(&lock) != 0)
		abort();
	result = check();
	return NULL;
}

int
main(int argc, char **argv)
{
	unsigned int round;
	if (argc != 2)
		return 2;
	for (round = 0; round < 4; round++) {
		pthread_t thread;
		void *handle;
		uint32_t (*drops)(void);
		uint32_t previous, count;
		released = entered = 0;
		result = UINT32_MAX;
		if (pthread_create(&thread, NULL, worker, NULL) != 0)
			return 1;
		if (pthread_mutex_lock(&lock) != 0)
			return 1;
		while (!entered) {
			if (pthread_cond_wait(&ready, &lock) != 0)
				return 1;
		}
		/* The caller thread already exists when the Rust DSO is loaded. */
		handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
		if (handle == NULL) {
			fprintf(stderr, "dlopen: %s\n", dlerror());
			return 1;
		}
		check = (uint32_t (*)(void))dlsym(handle, "ember_rust_check");
		drops = (uint32_t (*)(void))dlsym(handle, "ember_rust_drops");
		if (check == NULL || drops == NULL)
			return 1;
		previous = drops();
		released = 1;
		if (pthread_cond_broadcast(&ready) != 0 ||
		    pthread_mutex_unlock(&lock) != 0)
			return 1;
		/* Join before dlclose so that all TLS destructors have returned. */
		if (pthread_join(thread, NULL) != 0 || result != 0)
			return 1;
		/* dlclose may keep the DSO resident; require this cycle's delta. */
		count = drops() - previous;
		printf("Rust C-thread cycle %u: %u TLS destructors\n",
		    round + 1, count);
		if (count != 9 || dlclose(handle) != 0)
			return 1;
	}
	puts("PASS: four Rust cdylib loads from existing C threads, TLS/unwind and external TLS destructor, join before dlclose");
	return 0;
}
