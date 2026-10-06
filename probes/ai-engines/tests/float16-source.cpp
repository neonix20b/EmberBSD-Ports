// SPDX-License-Identifier: MIT
#include <cmath>
#include <cstdio>
#include <limits>

#include "core/common/float16.h"

int main()
{
    using onnxruntime::BFloat16;
    const BFloat16 nan(std::numeric_limits<float>::quiet_NaN());
    const BFloat16 infinity(std::numeric_limits<float>::infinity());
    const BFloat16 negative(-1.5f);
    const BFloat16 zero(0.0f);
    if (!nan.IsNaN() || !std::isnan(nan.ToFloat()) ||
        !infinity.IsPositiveInfinity() || infinity.IsNaN() ||
        negative.ToFloat() != -1.5f || zero.ToFloat() != 0.0f) {
        std::fputs("BFloat16 conversion contract failed\n", stderr);
        return 1;
    }
    std::puts("PASS BFloat16 NaN, infinity, negative finite and zero");
    return 0;
}
