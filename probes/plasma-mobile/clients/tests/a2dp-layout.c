/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 EmberBSD contributors. AI-assisted contract probe. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "a2dp-codecs.h"

int
main(void)
{
	a2dp_sbc_t sbc = {0};
	const unsigned char expected[] = {0x22, 0x15, 0x02, 0x40};

	sbc.frequency = SBC_SAMPLING_FREQ_44100;
	sbc.channel_mode = SBC_CHANNEL_MODE_STEREO;
	sbc.block_length = SBC_BLOCK_LENGTH_16;
	sbc.subbands = SBC_SUBBANDS_8;
	sbc.allocation_method = SBC_ALLOCATION_LOUDNESS;
	sbc.min_bitpool = MIN_BITPOOL;
	sbc.max_bitpool = MAX_BITPOOL;
	if (sizeof(sbc) != sizeof(expected) ||
	    memcmp(&sbc, expected, sizeof(expected)) != 0) {
		fprintf(stderr, "A2DP SBC wire layout does not match expected bytes.\n");
		return EXIT_FAILURE;
	}
	puts("A2DP SBC wire layout passed.");
	return EXIT_SUCCESS;
}
