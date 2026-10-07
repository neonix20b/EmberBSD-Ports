/* SPDX-License-Identifier: MIT */
#include <stdint.h>
#include <stdio.h>
int
main(int argc, char **argv)
{
	FILE *f;
	unsigned n, k;
	if (argc != 2 || (f = fopen(argv[1], "wb")) == NULL)
		return 1;
	for (n = 0; n < 4096; n++) {
		int16_t iq[2] = { (int16_t)((int)(n % 31) - 15), (int16_t)(100 - n % 17) };
		for (k = 0; k < 2; k++) {
			uint16_t v = (uint16_t)iq[k];
			if (fputc(v & 255, f) == EOF || fputc(v >> 8, f) == EOF)
				return 1;
		}
	}
	return fclose(f) != 0;
}
