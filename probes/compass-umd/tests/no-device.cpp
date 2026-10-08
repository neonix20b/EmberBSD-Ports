// SPDX-License-Identifier: BSD-2-Clause
// Origin: EmberBSD, AI-assisted public API consumer. No modeled UMD or device.
#include <sys/resource.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <link.h>
#include <unistd.h>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <standard_api.h>

#if !defined(__NetBSD__) || !defined(__aarch64__)
#error "This no-device execution probe requires NetBSD/AArch64"
#endif

static unsigned checks;
static void
check(bool ok, const char *what)
{
    if (!ok) {
        std::fprintf(stderr, "FAIL: %s\n", what);
        std::exit(1);
    }
    ++checks;
}

static std::string
canonical(const char *path)
{
    char *p = realpath(path, nullptr);
    if (!p)
        return {};
    std::string result(p);
    std::free(p);
    return result;
}

static void
no_device()
{
    struct stat sb;
    errno = 0;
    check(lstat("/dev/aipu", &sb) == -1 && errno == ENOENT,
        "requires /dev/aipu absent, including symlinks");
}

static unsigned
fd_count()
{
    struct rlimit limit;
    check(getrlimit(RLIMIT_NOFILE, &limit) == 0 && limit.rlim_cur <= 65536,
        "bounded descriptor table");
    unsigned count = 0;
    for (int fd = 0; static_cast<rlim_t>(fd) < limit.rlim_cur; ++fd) {
        errno = 0;
        int flags = fcntl(fd, F_GETFD);
        if (flags == -1 && errno != EBADF)
            check(false, "descriptor query");
        count += flags != -1;
    }
    return count;
}

struct providers {
    std::string library, executable;
    unsigned umd = 0, cxx = 0, gcc = 0;
};

static int
loaded(struct dl_phdr_info *info, size_t, void *opaque)
{
    auto *p = static_cast<providers *>(opaque);
    if (!info->dlpi_name || !*info->dlpi_name)
        return 0;
    auto path = canonical(info->dlpi_name);
    if (path.empty()) {
        std::fprintf(stderr, "FAIL: unresolved loaded provider: %s\n", info->dlpi_name);
        return 1;
    }
    if (path == p->executable)
        return 0;
    std::printf("LOADED: %s\n", path.c_str());
    if (path == p->library)
        ++p->umd;
    else if (path.find("/usr/pkg/gcc16/lib/libstdc++.so.") == 0)
        ++p->cxx;
    else if (path.find("/usr/pkg/gcc16/lib/libgcc_s.so.") == 0)
        ++p->gcc;
    else if (path.find("/usr/lib/") != 0 && path.find("/lib/") != 0 &&
        path != "/usr/libexec/ld.elf_so" && path != "/libexec/ld.elf_so") {
        std::fprintf(stderr, "FAIL: foreign loaded provider: %s\n", path.c_str());
        return 1;
    }
    return 0;
}

template<typename Function>
static Function
symbol(void *handle, const char *name, const std::string &expected)
{
    dlerror();
    void *address = dlsym(handle, name);
    check(address != nullptr && dlerror() == nullptr, name);
    Dl_info info{};
    check(dladdr(address, &info) != 0 && info.dli_fname != nullptr &&
        canonical(info.dli_fname) == expected, "public symbol belongs to exact full UMD");
    return reinterpret_cast<Function>(address);
}

int
main(int argc, char **argv)
{
    check(argc == 2 && argv[1][0] == '/', "absolute private UMD path required");
    const auto library = canonical(argv[1]);
    check(!library.empty() && library == argv[1], "canonical exact UMD path");
    const auto executable = canonical(argv[0]);
    check(!executable.empty(), "absolute executable path");
    no_device();
    const unsigned before = fd_count();
    for (unsigned cycle = 0; cycle < 4; ++cycle) {
        no_device();
        void *handle = dlopen(library.c_str(), RTLD_NOW | RTLD_LOCAL);
        if (!handle)
            std::fprintf(stderr, "dlopen: %s\n", dlerror());
        check(handle != nullptr, "load complete DSO with immediate binding");
        auto init = symbol<decltype(&aipu_init_context)>(handle, "aipu_init_context", library);
        auto deinit = symbol<decltype(&aipu_deinit_context)>(handle, "aipu_deinit_context", library);
        auto error = symbol<decltype(&aipu_get_error_message)>(handle, "aipu_get_error_message", library);
        check(init(nullptr) == AIPU_STATUS_ERROR_NULL_PTR, "null init output rejected");
        aipu_ctx_handle_t *ctx = reinterpret_cast<aipu_ctx_handle_t *>(1);
        no_device();
        check(init(&ctx) == AIPU_STATUS_ERROR_OPEN_DEV_FAIL, "real device open failure propagated");
        check(ctx == nullptr, "failed context output cleared");
        check(deinit(ctx) == AIPU_STATUS_ERROR_NULL_PTR, "no context to destroy after failure");
        aipu_ctx_handle_t invalid{};
        check(deinit(&invalid) == AIPU_STATUS_ERROR_INVALID_CTX, "unknown context rejected");
        const char *message = nullptr;
        check(error(nullptr, AIPU_STATUS_ERROR_OPEN_DEV_FAIL, &message) ==
            AIPU_STATUS_ERROR_OPEN_DEV_FAIL && message && *message,
            "real static open-failure message");
        std::printf("OPEN_ERROR: %s\n", message);
        check(error(nullptr, AIPU_STATUS_ERROR_OPEN_DEV_FAIL, nullptr) ==
            AIPU_STATUS_ERROR_NULL_PTR, "null error-message output rejected");
        providers state{library, executable};
        const int inventory = dl_iterate_phdr(loaded, &state);
        // Never exit in the loader callback: release the caller's handle first.
        const int closed = dlclose(handle);
        check(inventory == 0 && state.umd == 1 && state.cxx == 1 && state.gcc == 1,
            "one exact UMD and one canonical GCC16 runtime");
        check(closed == 0, "dlclose");
        check(fd_count() == before, "no descriptor leak across public failure lifecycle");
        std::printf("PASS: no-device public lifecycle cycle %u\n", cycle + 1);
    }
    std::printf("PASS: full UMD no-device API, %u checks; no device/model execution\n", checks);
    return 0;
}
