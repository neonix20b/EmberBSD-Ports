/* SPDX-License-Identifier: MIT */
#include <rnnoise.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define FRAMES	300

#define CHECK(x) do {							\
	if (!(x)) {							\
		fprintf(stderr, "Failed: %s\n", #x);			\
		status = 1;						\
		goto done;						\
	}								\
} while (0)

static int
process(DenoiseState *state, const float *input, size_t samples, float *output)
{
	int frame, i;
	size_t pos;
	float probability;

	frame = rnnoise_get_frame_size();
	if (state == NULL || input == NULL || output == NULL || frame <= 0 ||
	    samples % (size_t)frame != 0)
		return -1;

	/* Validate before touching the recurrent state. */
	for (pos = 0; pos < samples; ++pos) {
		if (!isfinite(input[pos]))
			return -1;
	}
	for (pos = 0; pos < samples; pos += (size_t)frame) {
		probability = rnnoise_process_frame(state, output + pos,
		    input + pos);
		if (!isfinite(probability) || probability < 0 || probability > 1)
			return -1;
		for (i = 0; i < frame; ++i) {
			if (!isfinite(output[pos + (size_t)i]))
				return -1;
		}
	}
	return 0;
}

int
main(void)
{
	const size_t chunks[] = {1, 7, 2, 13, 3};
	DenoiseState *a = NULL, *b = NULL;
	float *input = NULL, *whole = NULL, *chunked = NULL;
	double energy = 0, tail = 0;
	size_t samples = (size_t)FRAMES * 480;
	size_t count, i, pos = 0, turn = 0;
	uint32_t random = 1;
	int frame, status = 0;

	frame = rnnoise_get_frame_size();
	CHECK(frame == 480);
	input = calloc(samples, sizeof(*input));
	whole = malloc(samples * sizeof(*whole));
	chunked = malloc(samples * sizeof(*chunked));
	a = rnnoise_create(NULL);
	b = rnnoise_create(NULL);
	CHECK(input && whole && chunked && a && b);

	for (i = 4800; i < samples - 48000; ++i) {
		random = random * 1664525u + 1013904223u;
		input[i] = 6000.0f * (float)sin(2.0 * 3.141592653589793 *
		    220.0 * (double)i / 48000.0) +
		    (float)((int)(random >> 16) - 32768) / 20.0f;
	}
	CHECK(process(a, input, samples, whole) == 0);
	while (pos < samples) {
		count = chunks[turn++ % 5] * (size_t)frame;
		if (count > samples - pos)
			count = samples - pos;
		CHECK(process(b, input + pos, count, chunked + pos) == 0);
		pos += count;
	}
	for (i = 0; i < samples; ++i) {
		CHECK(fabsf(whole[i] - chunked[i]) <= 1e-4f);
		energy += (double)whole[i] * whole[i];
		if (i >= samples - 4800)
			tail += (double)whole[i] * whole[i];
	}
	CHECK(energy > 1.0 && tail < 1.0);
	CHECK(process(b, input, 479, chunked) == -1);
	input[0] = NAN;
	CHECK(process(b, input, 480, chunked) == -1);
	input[0] = 0;
	CHECK(process(NULL, input, 480, chunked) == -1);
	printf("PASS RNNoise: %zu input/output samples, streaming continuity, "
	    "finite output, silence tail, invalid chunk/NaN rejection\n", samples);

done:
	if (a)
		rnnoise_destroy(a);
	if (b)
		rnnoise_destroy(b);
	free(input);
	free(whole);
	free(chunked);
	return status;
}
