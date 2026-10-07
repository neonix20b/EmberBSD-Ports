// SPDX-License-Identifier: MIT
// Copyright (c) 2026 EmberBSD contributors
#include <volk/volk.h>
#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <stdexcept>
#include <string>

namespace {
constexpr unsigned capacity = 1032;
constexpr float sentinel = -987654.0f;
const unsigned lengths[] = {0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17,
                            31, 32, 33, 63, 64, 65, 127, 255, 511, 1023};

template <class T> struct Buffer {
    T* base;
    T* data;
    explicit Buffer(unsigned offset) {
        base = static_cast<T*>(volk_malloc(sizeof(T) * (capacity + 32), volk_get_alignment()));
        if (!base) throw std::bad_alloc();
        // Leave guards before and after the payload; maintain SIMD alignment at offset 0.
        data = base + 16 + offset;
        for (unsigned i = 0; i < capacity + 32; ++i) new (base + i) T{};
    }
    ~Buffer() { volk_free(base); }
    Buffer(const Buffer&) = delete;
    Buffer& operator=(const Buffer&) = delete;
};

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

void close(float actual, double expected, double tolerance, const std::string& context) {
    if (!std::isfinite(actual) || std::abs(actual - expected) >
        tolerance * std::max(1.0, std::abs(expected))) {
        char values[160];
        std::snprintf(values, sizeof(values), ": actual=%.9g expected=%.12g tolerance=%.6g",
                      actual, expected, tolerance);
        throw std::runtime_error(context + values);
    }
}

volk_func_desc_t descriptor(const std::string& kernel) {
    if (kernel == "dot") return volk_32f_x2_dot_prod_32f_get_func_desc();
    if (kernel == "multiply") return volk_32f_x2_multiply_32f_get_func_desc();
    if (kernel == "magnitude") return volk_32fc_magnitude_32f_get_func_desc();
    throw std::runtime_error("Unknown kernel");
}

void run(const std::string& kernel, const char* implementation, unsigned n,
         unsigned offset) {
    Buffer<float> a(offset), b(offset), output(offset);
    Buffer<lv_32fc_t> complex_input(offset);
    for (unsigned i = 0; i < capacity; ++i) {
        a.data[i] = static_cast<float>(static_cast<int>(i % 29) - 14) / 8.0f;
        b.data[i] = static_cast<float>(static_cast<int>((i * 7) % 31) - 15) / 16.0f;
        complex_input.data[i] = lv_32fc_t(a.data[i], b.data[i]);
        output.data[i] = sentinel;
    }
    output.data[-1] = sentinel;
    const std::string mode = implementation ? implementation : "dispatch";
    const std::string context = kernel + "/" + mode + "/n=" + std::to_string(n) +
        "/offset=" + std::to_string(offset);
    if (kernel == "dot") {
        if (implementation)
            volk_32f_x2_dot_prod_32f_manual(output.data, a.data, b.data, n, implementation);
        else
            volk_32f_x2_dot_prod_32f(output.data, a.data, b.data, n);
        double reference = 0;
        for (unsigned i = 0; i < n; ++i)
            reference += static_cast<double>(a.data[i]) * b.data[i];
        close(output.data[0], reference, 2e-5, context);
    } else if (kernel == "multiply") {
        if (implementation)
            volk_32f_x2_multiply_32f_manual(output.data, a.data, b.data, n, implementation);
        else
            volk_32f_x2_multiply_32f(output.data, a.data, b.data, n);
        for (unsigned i = 0; i < n; ++i)
            close(output.data[i], static_cast<double>(a.data[i]) * b.data[i], 2e-6, context);
    } else {
        if (implementation)
            volk_32fc_magnitude_32f_manual(output.data, complex_input.data, n, implementation);
        else
            volk_32fc_magnitude_32f(output.data, complex_input.data, n);
        // Upstream's older NEON magnitude kernels intentionally approximate sqrt.
        // The ARMv8 sqrt kernel, generic path and default dispatch stay strict.
        double tolerance = 2e-6;
        if (mode == "neon") tolerance = 5e-3;
        if (mode == "neon_fancy_sweet") tolerance = 1.5e-2;
        for (unsigned i = 0; i < n; ++i)
            close(output.data[i], std::hypot(static_cast<double>(a.data[i]),
                                          static_cast<double>(b.data[i])), tolerance, context);
    }
    require(output.data[-1] == sentinel, context + ": leading output guard changed");
    const unsigned written = kernel == "dot" ? 1 : n;
    for (unsigned i = written; i < capacity; ++i)
        require(output.data[i] == sentinel, context + ": output tail changed");
    for (unsigned i = 0; i < capacity; ++i) {
        require(complex_input.data[i] == lv_32fc_t(a.data[i], b.data[i]),
                context + ": input changed");
        require(a.data[i] == static_cast<float>(static_cast<int>(i % 29) - 14) / 8.0f &&
                b.data[i] == static_cast<float>(static_cast<int>((i * 7) % 31) - 15) / 16.0f,
                context + ": scalar input changed");
    }
}
} // namespace

int main(int argc, char** argv) {
    try {
        require(argc == 2, "Usage: volk-contract dot|multiply|magnitude");
        const std::string kernel = argv[1];
        require(std::strcmp(volk_get_machine(), "neonv8") == 0, "Expected neonv8 machine");
        require(volk_get_alignment() == 16, "Expected 16-byte NEON alignment");
        Buffer<float> aligned(0), unaligned(1);
        require(volk_is_aligned(aligned.data), "Aligned allocation is misaligned");
        require(!volk_is_aligned(unaligned.data), "Unaligned fixture is aligned");
        const auto desc = descriptor(kernel);
        bool generic = false, neon = false;
        unsigned cases = 0;
        std::printf("machine=%s alignment=%zu mode=%s kernel=%s implementations=",
                    volk_get_machine(), volk_get_alignment(),
                    std::getenv("VOLK_GENERIC") ? "forced-generic" : "automatic", argv[1]);
        for (size_t i = 0; i < desc.n_impls; ++i) {
            std::printf("%s%s", i ? "," : "", desc.impl_names[i]);
            generic |= std::strcmp(desc.impl_names[i], "generic") == 0;
            neon |= std::strstr(desc.impl_names[i], "neon") != nullptr;
            for (unsigned offset : {0u, 1u}) {
                if (offset && desc.impl_alignment[i]) continue;
                for (unsigned n : lengths) {
                    run(kernel, desc.impl_names[i], n, offset);
                    ++cases;
                }
            }
        }
        require(generic && neon, "Missing generic or NEON implementation");
        for (unsigned offset : {0u, 1u})
            for (unsigned n : lengths) {
                run(kernel, nullptr, n, offset);
                ++cases;
            }
        std::printf(" cases=%u PASS\n", cases);
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "FAIL: %s\n", error.what());
        return 1;
    }
}
