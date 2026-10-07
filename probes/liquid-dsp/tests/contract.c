/* SPDX-License-Identifier: MIT */
#include <complex.h>
#include <liquid/liquid.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const double pi = 3.14159265358979323846;
static void check(int ok, const char *what)
{
    if (!ok) { fprintf(stderr, "FAIL: %s\n", what); exit(1); }
}
static float complex tone(double frequency, unsigned sample)
{
    double phase = 2 * pi * frequency * sample;
    return cos(phase) + I * sin(phase);
}
static void filter_case(void)
{
    const unsigned length = 129, count = 2048;
    const double frequencies[] = {0.03, 0.31};
    double gain[2];
    for (unsigned band = 0; band < 2; ++band) {
        firfilt_crcf q = firfilt_crcf_create_kaiser(length, 0.12f, 80, 0);
        check(q != NULL, "filter create");
        check(firfilt_crcf_set_scale(q, 0.24f) == LIQUID_OK, "filter scale");
        double power = 0;
        for (unsigned i = 0; i < count; ++i) {
            float complex output;
            check(firfilt_crcf_push(q, tone(frequencies[band], i)) == LIQUID_OK, "filter push");
            check(firfilt_crcf_execute(q, &output) == LIQUID_OK, "filter execute");
            if (i >= length) power += crealf(output * conjf(output));
        }
        gain[band] = sqrt(power / (count - length));
        check(firfilt_crcf_destroy(q) == LIQUID_OK, "filter destroy");
    }
    check(fabs(gain[0] - 1) < 0.005, "passband gain within 0.5 percent");
    check(gain[1] < 0.001, "stopband below -60 dB");
    printf("PASS filter passband=%.8f stopband=%.2f dB\n", gain[0], 20 * log10(gain[1]));
}
static void resample_case(void)
{
    const unsigned input_count = 2048;
    const double rate = 1.5, input_frequency = 0.06;
    resamp_crcf q = resamp_crcf_create(rate, 12, 0.4f, 80, 64);
    check(q != NULL, "resampler create");
    unsigned total = 0, valid = 0;
    double amplitude = 0;
    double complex correlation = 0;
    float complex previous = 0;
    for (unsigned i = 0; i < input_count; ++i) {
        float complex output[2];
        unsigned written = 0;
        check(resamp_crcf_execute(q, tone(input_frequency, i), output, &written) == LIQUID_OK, "resample execute");
        check(written <= 2, "resample output bound");
        for (unsigned j = 0; j < written; ++j) {
            if (total > 100) {
                amplitude += cabsf(output[j]);
                correlation += output[j] * conjf(previous);
                ++valid;
            }
            previous = output[j]; ++total;
        }
    }
    double frequency = carg(correlation) / (2 * pi);
    double gain = amplitude / valid;
    check(abs((int)total - (int)(input_count * rate)) <= 1, "3:2 output count");
    check(fabs(frequency - input_frequency / rate) < 1e-5, "physical tone frequency after resampling");
    check(fabs(gain - 1) < 0.01, "resampler amplitude preservation");
    check(resamp_crcf_destroy(q) == LIQUID_OK, "resampler destroy");
    printf("PASS resample input=%u output=%u normalized-frequency=%.8f gain=%.8f\n", input_count, total, frequency, gain);
}
static uint32_t rng_state = 0x49eab127U;
static uint32_t random_word(void)
{
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}
static float noise(void)
{
    return ((random_word() & 0xffffU) / 65535.0f - 0.5f) * 0.3f;
}
static void modem_case(void)
{
    modemcf tx = modemcf_create(LIQUID_MODEM_QPSK), rx = modemcf_create(LIQUID_MODEM_QPSK);
    check(tx && rx, "QPSK modems");
    unsigned errors = 0, inverted_errors = 0, seen = 0;
    for (unsigned i = 0; i < 4096; ++i) {
        unsigned symbol = (random_word() >> 16) & 3, decoded;
        float complex point;
        check(modemcf_modulate(tx, symbol, &point) == LIQUID_OK, "QPSK modulation");
        check(fabs(cabsf(point) - 1) < 1e-6, "unit-energy QPSK");
        check(fabs(fabs(crealf(point)) - sqrt(0.5)) < 1e-6 &&
            fabs(fabs(cimagf(point)) - sqrt(0.5)) < 1e-6, "QPSK constellation coordinates");
        seen |= 1U << symbol;
        float nr = noise(), ni = noise();
        float complex received = point + nr + I * ni;
        check(modemcf_demodulate(rx, received, &decoded) == LIQUID_OK, "QPSK demodulation");
        errors += decoded != symbol;
        check(modemcf_demodulate(rx, -received, &decoded) == LIQUID_OK, "QPSK deliberate phase inversion");
        inverted_errors += decoded != symbol;
    }
    check(seen == 15 && errors == 0, "all symbols recovered under bounded deterministic noise");
    check(inverted_errors == 4096, "negative control detects inverted constellation");
    modemcf_destroy(tx); modemcf_destroy(rx);
    printf("PASS QPSK symbols=4096 symbol-errors=%u inverted-symbol-errors=%u\n", errors, inverted_errors);
}
static void spectrum_case(void)
{
    const unsigned nfft = 256;
    spgramcf q = spgramcf_create_default(nfft);
    check(q != NULL, "spectrum create");
    float complex block[256];
    for (unsigned batch = 0; batch < 32; ++batch) {
        for (unsigned j = 0; j < nfft; ++j)
            block[j] = tone(0.125, batch * nfft + j);
        check(spgramcf_write(q, block, nfft) == LIQUID_OK, "spectrum write");
    }
    float psd[256];
    check(spgramcf_get_psd(q, psd) == LIQUID_OK, "spectrum PSD");
    unsigned peak = 0;
    for (unsigned j = 0; j < nfft; ++j) {
        check(isfinite(psd[j]), "finite PSD");
        if (psd[j] > psd[peak]) peak = j;
    }
    check(peak == nfft / 2 + nfft / 8, "FFT-shifted peak at physical tone frequency");
    check(psd[peak] - psd[32] > 60, "spectral rejection away from tone");
    spgramcf_destroy(q);
    printf("PASS FFTW spectrum peak-bin=%u frequency=0.125 rejection=%.2f dB\n", peak, psd[peak] - psd[32]);
}
int main(int argc, char **argv)
{
    check(argc == 2, "one case name required");
    check(strcmp(liquid_libversion(), "1.8.3") == 0, "installed runtime version");
    check(liquid_libversion_number() == LIQUID_VERSION_NUMBER, "header/runtime ABI version");
    if (!strcmp(argv[1], "filter")) filter_case();
    else if (!strcmp(argv[1], "resample")) resample_case();
    else if (!strcmp(argv[1], "modem")) modem_case();
    else if (!strcmp(argv[1], "spectrum")) spectrum_case();
    else check(0, "unknown case");
    return 0;
}
