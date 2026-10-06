// SPDX-License-Identifier: MIT
#pragma once
#include <pthread.h>
#include <sched.h>
#include <cerrno>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

struct CpusetDeleter {
    void operator()(cpuset_t *set) const { cpuset_destroy(set); }
};
using CpuSet = std::unique_ptr<cpuset_t, CpusetDeleter>;

class CpuBinding {
public:
    CpuBinding() : saved_(cpuset_create()), selected_(cpuset_create()) {
        if (!saved_ || !selected_ ||
            pthread_getaffinity_np(pthread_self(), cpuset_size(saved_.get()), saved_.get()) != 0)
            throw std::runtime_error("cannot save thread affinity");
    }
    ~CpuBinding() {
        if (changed_ && pthread_setaffinity_np(pthread_self(), cpuset_size(saved_.get()), saved_.get()) != 0)
            std::terminate();
    }
    int bind(cpuid_t cpu) {
        cpuset_zero(selected_.get());
        if (cpuset_set(cpu, selected_.get()) != 0) return errno;
        const int result = pthread_setaffinity_np(pthread_self(), cpuset_size(selected_.get()), selected_.get());
        if (result == 0) changed_ = true;
        return result;
    }
private:
    CpuSet saved_, selected_;
    bool changed_ = false;
};

// Probe configured IDs through the kernel: offline holes may reject a binding.
// Policy denial is a reported failure, never a successful/skipped acceptance.
static std::vector<cpuid_t> two_available_cpus(long configured)
{
    CpuBinding binding;
    std::vector<cpuid_t> result;
    for (long cpu = 0; cpu < configured && result.size() < 2; ++cpu) {
        const int error = binding.bind(static_cast<cpuid_t>(cpu));
        if (error == 0) result.push_back(static_cast<cpuid_t>(cpu));
        else if (error != EINVAL)
            throw std::runtime_error("CPU affinity denied/failed: " + std::to_string(error));
    }
    if (result.size() != 2) throw std::runtime_error("two available CPUs required for affinity acceptance");
    return result;
}
