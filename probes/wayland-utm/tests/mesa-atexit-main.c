/* Origin: EmberBSD; AI-assisted production-helper DSO regression.
 * SPDX-License-Identifier: BSD-2-Clause
 */
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int events[16];
static unsigned count;
void
record_event(int event)
{
	assert(count < sizeof(events) / sizeof(events[0]));
	events[count++] = event;
	printf("event %d\n", event);
	fflush(stdout);
}
static void *
open_dso(const char *path, int start)
{
	void *handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
	if (handle == NULL) {
		fprintf(stderr, "%s\n", dlerror());
		exit(2);
	}
	if (start) {
		void (*init)(void) = (void (*)(void))dlsym(handle, "start_callbacks");
		assert(init != NULL);
		init();
	}
	return handle;
}
static void
expect(unsigned start, int id)
{
	assert(count == start + 4);
	for (unsigned i = 0; i < 4; i++)
		assert(events[start + i] == id * 10 + 4 - (int)i);
}
int
main(int argc, char **argv)
{
	assert(argc == 4);
	if (strcmp(argv[1], "exit") == 0) {
		open_dso(argv[2], 1);
		open_dso(argv[3], 1);
		return 0;
	}
	assert(strcmp(argv[1], "close") == 0);
	void *unused = open_dso(argv[2], 0);
	assert(dlclose(unused) == 0 && count == 0);
	for (unsigned i = 0; i < 64; i++) {
		count = 0;
		void *a = open_dso(argv[2], 1);
		void *b = open_dso(argv[3], 1);
		assert(dlclose(a) == 0);
		expect(0, 1);
		assert(dlclose(b) == 0);
		expect(4, 2);
	}
	puts("64 two-owner unload cycles and unused DSO: PASS");
	return 0;
}
