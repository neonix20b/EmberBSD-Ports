// SPDX-License-Identifier: MIT
#include <unistd.h>
#include <cstdio>
#include <thread>
#include <cstring>
#include <exception>
#include "netbsd-affinity.h"

#include "core/platform/posix/netbsd_cpu.h"

static int check_cpu(long count)
{
    for (int i = 0; i < 1000; ++i) {
        const int cpu = onnxruntime::GetNetBSDCurrentCpu();
        if (cpu < 0 || cpu >= count)
            return 1;
    }
    return 0;
}

int main(int argc, char **argv) try
{
    if (argc > 2 || (argc == 2 && std::strcmp(argv[1], "--affinity") != 0))
        return 2;
    const long count = sysconf(_SC_NPROCESSORS_CONF);
    if (count < 1 || check_cpu(count) != 0)
        return 1;
    int worker_result = 1;
    std::thread worker([&] { worker_result = check_cpu(count); });
    worker.join();
    if (worker_result != 0)
        return 1;
    std::printf("PASS NetBSD current CPU: 1000 samples each in main and worker, %ld CPUs\n", count);
    if (argc == 2) {
        const auto available = two_available_cpus(count);
        std::exception_ptr failure;
        std::thread pinned_worker([&] {
            try {
                CpuBinding binding;
                for (cpuid_t cpu : available) {
                    if (binding.bind(cpu) != 0)
                        throw std::runtime_error("worker affinity failed");
                    for (int i = 0; i < 1000; ++i)
                        if (onnxruntime::GetNetBSDCurrentCpu() != static_cast<int>(cpu))
                            throw std::runtime_error("current CPU disagrees with worker affinity");
                }
            } catch (...) { failure = std::current_exception(); }
        });
        pinned_worker.join();
        if (failure) std::rethrow_exception(failure);
        std::printf("PASS NetBSD current CPU follows worker affinity: CPU %lu then CPU %lu\n",
            static_cast<unsigned long>(available[0]), static_cast<unsigned long>(available[1]));
    }
    return 0;
} catch (const std::exception &error) { std::fprintf(stderr, "%s\n", error.what()); return 1; }
