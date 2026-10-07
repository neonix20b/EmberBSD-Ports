/* SPDX-License-Identifier: MIT */
#include "liquid.internal.h"
#include <math.h>
#if !fftw3f_FOUND
#error FFTW_BACKEND_REQUIRED
#endif
int
main(void)
{
    float complex input[8] = {1}, output[8];
    FFT_PLAN plan = FFT_CREATE_PLAN(8, input, output, FFT_DIR_FORWARD, FFT_METHOD);
    if (!plan) return 1;
    FFT_EXECUTE(plan);
    FFT_DESTROY_PLAN(plan);
    for (unsigned i = 0; i < 8; ++i) {
        float error = cabsf(output[i] - 1);
        if (!isfinite(crealf(output[i])) || !isfinite(cimagf(output[i])) ||
            !isfinite(error) || error > 1e-6f) return 1;
    }
    return 0;
}
