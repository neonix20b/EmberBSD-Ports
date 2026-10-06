/* SPDX-License-Identifier: MIT */
#define _NETBSD_SOURCE
#include <sys/mman.h>
#include <fcntl.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <string.h>

int main(void)
{
    const size_t lengths[] = {4095, 4096, 4097, 1920000};
    const size_t page = (size_t)getpagesize();
    unsigned int i;
    int rounded, failures = 0;
    printf("page_size=%zu prot=READ|WRITE flags=MAP_SHARED offset=0\n", page);
    for (i = 0; i < sizeof(lengths) / sizeof(lengths[0]); i++) {
        for (rounded = 0; rounded <= 1; rounded++) {
            const size_t n = lengths[i];
            const size_t allocated = rounded ? (n + page - 1) / page * page : n;
            int fd = memfd_create("kwin-mmap-probe", MFD_CLOEXEC | MFD_ALLOW_SEALING);
            if (fd < 0 || ftruncate(fd, (off_t)allocated) != 0) {
                perror("memfd_create/ftruncate");
                return 1;
            }
            errno = 0;
            void *p = mmap(NULL, n, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
            const int map_errno = p == MAP_FAILED ? errno : 0;
            printf("requested=%zu truncated=%zu mmap=%s errno=%d\n", n, allocated,
                p == MAP_FAILED ? "FAIL" : "PASS", map_errno);
            if (p != MAP_FAILED) {
                memset(p, 0x45, n);
                munmap(p, n);
            } else {
                failures++;
            }
            close(fd);
        }
    }
    printf("failed_cases=%d\n", failures);
    return 0;
}
