/* Exercise GTK's actual pool allocation against the native kernel. */
#include <sys/mman.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <glib.h>
#ifndef TEST_SHM_OPEN
#define HAVE_MEMFD_CREATE 1
#endif
struct wl_shm;
struct wl_shm_pool;
static int peer_fd = -1;
static int pool_size;
static struct wl_shm_pool *
wl_shm_create_pool(struct wl_shm *shm, int fd, int size)
{
	(void)shm;
	peer_fd = dup(fd);
	if (peer_fd < 0)
		g_error("dup: %s", g_strerror(errno));
	pool_size = size;
	return (struct wl_shm_pool *)&peer_fd;
}
#include "gtk-shm-functions.c"
int
main(void)
{
	long page = sysconf(_SC_PAGESIZE);
	int failures = 0;
	g_assert_cmpint(page, >, 1);
	int sizes[] = {1, (int)page - 1, (int)page, (int)page + 1,
	    801360, 360 * 540 * 4};
	for (size_t i = 0; i < G_N_ELEMENTS(sizes); i++) {
		void *data = NULL;
		size_t length = 0;
		struct wl_shm_pool *pool = create_shm_pool(NULL, sizes[i],
		    &length, &data);
		if (pool == NULL) {
			printf("FAIL: pool size %d\n", sizes[i]);
			failures++;
			continue;
		}
		g_assert_cmpuint(length, ==, (size_t)sizes[i]);
		g_assert_cmpint(pool_size, ==, sizes[i]);
		unsigned char *peer = mmap(NULL, length, PROT_READ | PROT_WRITE,
		    MAP_SHARED, peer_fd, 0);
		g_assert_true(peer != MAP_FAILED);
		unsigned char *bytes = data;
		g_assert_cmpuint(peer[0], ==, 0);
		g_assert_cmpuint(peer[length - 1], ==, 0);
		bytes[0] = 0x37;
		g_assert_cmpuint(peer[0], ==, 0x37);
		peer[length - 1] = 0x59;
		g_assert_cmpuint(bytes[length - 1], ==, 0x59);
		g_assert_cmpint(munmap(peer, length), ==, 0);
		g_assert_cmpint(munmap(data, length), ==, 0);
		g_assert_cmpint(close(peer_fd), ==, 0);
		peer_fd = -1;
		printf("PASS: pool size %d, shared read/write and zero fill\n",
		    sizes[i]);
	}
	return failures != 0;
}
