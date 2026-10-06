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
    int write_seal;
    for (i = 0; i < sizeof(lengths) / sizeof(lengths[0]); i++) {
        for (write_seal = 0; write_seal <= 1; write_seal++) {
            const size_t n = lengths[i];
            const size_t allocated = (n + page - 1) / page * page;
            const int seals = F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_SEAL |
                (write_seal ? F_SEAL_WRITE : 0);
            int fd = memfd_create("kwin-seals-probe", MFD_CLOEXEC | MFD_ALLOW_SEALING);
            if (fd < 0 || ftruncate(fd, (off_t)allocated) != 0) return 1;
            unsigned char *p = mmap(NULL, n, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
            if (p == MAP_FAILED) return 2;
            memset(p, 0x45, n);
            munmap(p, n);
            if (fcntl(fd, F_ADD_SEALS, seals) != 0) return 3;
            const int actual = fcntl(fd, F_GET_SEALS);
            if (actual < 0 || (actual & seals) != seals) return 4;
            if (ftruncate(fd, (off_t)allocated + (off_t)page) != -1 || errno != EPERM) return 5;
            if (ftruncate(fd, 0) != -1 || errno != EPERM) return 6;
            p = mmap(NULL, n, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
            if (write_seal) {
                if (p != MAP_FAILED) return 7;
            } else {
                if (p == MAP_FAILED) return 8;
                p[0] = 0x46;
                munmap(p, n);
            }
            p = mmap(NULL, n, PROT_READ, MAP_PRIVATE, fd, 0);
            if (p == MAP_FAILED || p[0] != (write_seal ? 0x45 : 0x46) || p[n - 1] != 0x45) return 9;
            munmap(p, n);
            close(fd);
            printf("PASS logical=%zu physical=%zu seals=%#x write_seal=%d\n", n, allocated, actual, write_seal);
        }
    }
    return 0;
}
