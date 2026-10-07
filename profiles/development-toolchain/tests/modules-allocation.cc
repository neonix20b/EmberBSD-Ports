/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD; AI-assisted production allocation-lambda regression. */
#include <sys/types.h>
#include <cerrno>
#include <cstdio>
#include <initializer_list>


/* NetBSD keeps these errors distinct; the host may alias them. */
#undef ENOTSUP
#undef EOPNOTSUPP
#undef EINVAL
#define ENOTSUP 86
#define EOPNOTSUPP 45
#define EINVAL 22

static int allocation_result, truncate_result, allocation_calls, truncate_calls;
static bool arguments_ok;

static int
fake_posix_fallocate(int fd, off_t offset, off_t length)
{
    ++allocation_calls;
    arguments_ok = arguments_ok && fd == 7 && offset == 4096 && length == 8192;
    return allocation_result;
}

static int
fake_ftruncate(int fd, off_t length)
{
    ++truncate_calls;
    arguments_ok = arguments_ok && fd == 7 && length == 12288;
    return truncate_result;
}

#define posix_fallocate fake_posix_fallocate
#define ftruncate fake_ftruncate
static bool
production_allocate()
{
#include "allocation.inc"
    return allocate(7, 4096, 8192);
}
#undef posix_fallocate
#undef ftruncate

int
main()
{
    const int errors[] = { 0, EINVAL, ENOTSUP, EOPNOTSUPP, ENOSPC, EACCES, EBADF, EIO };
    unsigned failures = 0, cases = 0;
    for (int error : errors) {
        for (int truncate_status : { 0, -1 }) {
            allocation_result = error;
            truncate_result = truncate_status;
            allocation_calls = truncate_calls = 0;
            arguments_ok = true;
            /* The return code, not stale errno, decides the allocation branch. */
            errno = EACCES;
#ifdef HAVE_POSIX_FALLOCATE
            bool fallback = error == EINVAL || error == ENOTSUP || error == EOPNOTSUPP;
            bool expected = fallback ? truncate_status == 0 : error == 0;
            int expected_allocation_calls = 1;
#else
            bool fallback = true;
            bool expected = truncate_status == 0;
            int expected_allocation_calls = 0;
#endif
            bool actual = production_allocate();
            bool pass = actual == expected && arguments_ok &&
                allocation_calls == expected_allocation_calls &&
                truncate_calls == (fallback ? 1 : 0);
            std::printf("%s result=%d ftruncate=%d actual=%d allocation_calls=%d truncate_calls=%d\n",
                pass ? "PASS" : "FAIL", error, truncate_status, actual,
                allocation_calls, truncate_calls);
            failures += !pass;
            ++cases;
        }
    }
    std::printf("cases=%u failures=%u ENOTSUP=%d EOPNOTSUPP=%d\n",
        cases, failures, ENOTSUP, EOPNOTSUPP);
    return failures != 0;
}
