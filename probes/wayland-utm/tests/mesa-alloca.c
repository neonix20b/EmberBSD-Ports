/* SPDX-License-Identifier: BSD-2-Clause
 * Origin: EmberBSD; caller-stack allocation in Mesa's strict C/C++ modes.
 */
#include <stddef.h>
#include <stdint.h>
#include "c99_alloca.h"

__attribute__((noinline)) static int
clobber(int seed)
{
    volatile unsigned char temporary[256];
    unsigned int i;

    for (i = 0; i < sizeof temporary; i++)
        temporary[i] = (unsigned char)(seed + i);
    return temporary[127];
}

int
main(int argc, char **argv)
{
    volatile size_t requested = 137 + (unsigned)argc;
    volatile unsigned char *storage = (unsigned char *)alloca(requested + 32);
    size_t i;
    (void)argv;

#ifdef __cplusplus
    const size_t alignment = alignof(max_align_t);
#else
    const size_t alignment = _Alignof(max_align_t);
#endif
    if ((uintptr_t)storage % alignment != 0)
        return 3;
    for (i = 0; i < requested + 32; i++)
        storage[i] = 0xa5;
    for (i = 0; i < requested; i++)
        storage[i + 16] = (unsigned char)(3 * i + 7);
    if (clobber(19) != 146)
        return 1;
    for (i = 0; i < requested; i++)
        if (storage[i + 16] != (unsigned char)(3 * i + 7))
            return 2;
    for (i = 0; i < 16; i++)
        if (storage[i] != 0xa5 || storage[i + requested + 16] != 0xa5)
            return 4;
    return 0;
}
