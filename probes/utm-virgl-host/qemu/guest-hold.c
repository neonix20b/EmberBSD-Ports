/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD, AI-assisted isolated live-backing reset probe. */
#include <sys/types.h>
#include <sys/mman.h>
#include <err.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <xf86drm.h>
#include <drm.h>
#include <drm_mode.h>

int
main(void)
{
	struct drm_mode_create_dumb create = {
		.width = 64, .height = 16, .bpp = 32
	};
	struct drm_mode_map_dumb map = { 0 };
	volatile uint32_t *pixels;
	int fd;

	alarm(40);
	fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
	if (fd < 0 || drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) < 0)
		err(1, "create live dumb resource");
	if (create.size < 4096 || create.size > 1024 * 1024)
		errx(1, "unexpected dumb size");
	map.handle = create.handle;
	if (drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map) < 0)
		err(1, "map live dumb resource");
	pixels = mmap(NULL, create.size, PROT_READ | PROT_WRITE, MAP_SHARED,
	    fd, (off_t)map.offset);
	if (pixels == MAP_FAILED)
		err(1, "mmap live dumb resource");
	pixels[0] = UINT32_C(0x715bcafe);
	puts("EMBERGPU_LIVE_BACKING_READY");
	fflush(stdout);
	for (unsigned i = 0; i < 30; i++) {
		if (pixels[0] != UINT32_C(0x715bcafe))
			errx(1, "live backing changed");
		sleep(1);
	}
	/* A successful host test resets or quits before reaching this point. */
	errx(1, "host reset deadline expired");
}
