/* SPDX-License-Identifier: MIT */
#include <fftw3.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef USE_FLOAT
typedef float real;
#define FFT(name) fftwf_##name
#define TOL 2e-5
#define PRECISION "float"
#else
typedef double real;
#define FFT(name) fftw_##name
#define TOL 2e-12
#define PRECISION "double"
#endif
static const double pi = 3.14159265358979323846;
static void
check(int ok, const char *message)
{
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

static void
complex_case(int n, int threaded)
{
    FFT(complex) *input = FFT(alloc_complex)(n);
    FFT(complex) *output = FFT(alloc_complex)(n);
    FFT(complex) *back = FFT(alloc_complex)(n);
    check(input && output && back, "allocation");
    FFT(plan) forward = FFT(plan_dft_1d)(n, input, output, FFTW_FORWARD, FFTW_ESTIMATE);
    FFT(plan) inverse = FFT(plan_dft_1d)(n, output, back, FFTW_BACKWARD, FFTW_ESTIMATE);
    check(forward && inverse, "complex plans");
    for (int j = 0; j < n; ++j) {
        double angle = 2 * pi * j / n;
        input[j][0] = cos(3 * angle) + 0.25 * cos(7 * angle);
        input[j][1] = sin(3 * angle) - 0.25 * sin(7 * angle);
    }
    FFT(execute)(forward);
    double worst_spectrum = 0, worst_roundtrip = 0;
    for (int j = 0; j < n; ++j) {
        double expected = j == 3 ? 1 : (j == n - 7 ? 0.25 : 0);
        double error = hypot(output[j][0] / n - expected, output[j][1] / n);
        check(isfinite(error), "finite complex spectrum");
        if (error > worst_spectrum) worst_spectrum = error;
    }
    check(worst_spectrum < TOL, "analytical complex spectral peaks and empty bins");
    FFT(execute)(inverse);
    for (int j = 0; j < n; ++j) {
        double error = hypot(back[j][0] / n - input[j][0], back[j][1] / n - input[j][1]);
        check(isfinite(error), "finite complex inverse");
        if (error > worst_roundtrip) worst_roundtrip = error;
    }
    check(worst_roundtrip < TOL, "complex inverse normalization");
    printf("PASS %s complex n=%d threads=%d spectrum=%.3g inverse=%.3g\n",
        PRECISION, n, threaded ? 2 : 1, worst_spectrum, worst_roundtrip);
    FFT(destroy_plan)(forward); FFT(destroy_plan)(inverse);
    FFT(free)(input); FFT(free)(output); FFT(free)(back);
}

static void
real_case(int n)
{
    real *input = FFT(alloc_real)(n), *back = FFT(alloc_real)(n);
    FFT(complex) *output = FFT(alloc_complex)(n / 2 + 1);
    check(input && output && back, "real allocation");
    FFT(plan) forward = FFT(plan_dft_r2c_1d)(n, input, output, FFTW_ESTIMATE);
    FFT(plan) inverse = FFT(plan_dft_c2r_1d)(n, output, back, FFTW_ESTIMATE);
    check(forward && inverse, "real plans");
    for (int j = 0; j < n; ++j)
        input[j] = 0.2 + 0.7 * cos(2 * pi * 5 * j / n) + 0.3 * sin(2 * pi * 9 * j / n);
    FFT(execute)(forward);
    double worst = 0;
    for (int j = 0; j <= n / 2; ++j) {
        double re = j == 0 ? 0.2 : (j == 5 ? 0.35 : 0);
        double im = j == 9 ? -0.15 : 0;
        double error = hypot(output[j][0] / n - re, output[j][1] / n - im);
        check(isfinite(error), "finite real spectrum");
        if (error > worst) worst = error;
    }
    check(worst < TOL, "analytical real spectrum");
    FFT(execute)(inverse);
    for (int j = 0; j < n; ++j)
        check(fabs(back[j] / n - input[j]) < TOL, "real inverse normalization");
    printf("PASS %s real n=%d spectrum=%.3g\n", PRECISION, n, worst);
    FFT(destroy_plan)(forward); FFT(destroy_plan)(inverse);
    FFT(free)(input); FFT(free)(output); FFT(free)(back);
}

int
main(void)
{
    check(strstr(FFT(version), "fftw-3.3.11") != NULL, "runtime version");
    printf("Runtime: %s\n", FFT(version));
    complex_case(64, 0); complex_case(45, 0); complex_case(127, 0);
    real_case(64); real_case(75);
    check(FFT(init_threads)() != 0, "pthread initialization");
    FFT(plan_with_nthreads)(2);
    complex_case(4096, 1);
    FFT(cleanup_threads)();
    return 0;
}
