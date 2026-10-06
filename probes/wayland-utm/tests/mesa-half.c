/* Origin: EmberBSD; AI-assisted exhaustive production half conversion test.
 * SPDX-License-Identifier: BSD-2-Clause
 */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#if defined(__x86_64__) || defined(__i386__)
#include <xmmintrin.h>
#endif

float _mesa_half_to_float_slow(uint16_t);

static uint64_t
get_fp_control(void)
{
#if defined(__aarch64__)
	uint64_t value;
	__asm__ volatile("mrs %0, fpcr" : "=r"(value));
	return value;
#elif defined(__x86_64__) || defined(__i386__)
	return _mm_getcsr();
#else
#error This regression needs explicit floating-point flush control.
#endif
}
static void
set_fp_control(uint64_t value)
{
#if defined(__aarch64__)
	__asm__ volatile("msr fpcr, %0; isb" : : "r"(value) : "memory");
#else
	_mm_setcsr((unsigned)value);
#endif
}
int
main(void)
{
	const uint64_t saved = get_fp_control();
#if defined(__aarch64__)
	const uint64_t flush = UINT64_C(1) << 24;
#else
	const uint64_t flush = (UINT64_C(1) << 15) | (UINT64_C(1) << 6);
#endif
	unsigned failures = 0;
	for (unsigned mode = 0; mode < 2; mode++) {
		set_fp_control((saved & ~flush) | (mode ? flush : 0));
		for (unsigned h = 0; h < 65536; h++) {
			unsigned exponent = (h >> 10) & 31, mantissa = h & 1023;
			uint32_t expected, actual;
			if (exponent == 31) {
				expected = UINT32_C(0x7f800000) | (mantissa << 13);
				if (h & 0x8000)
					expected |= UINT32_C(0x80000000);
			} else {
				/* Independent reference: every finite binary16 is exactly
				 * representable in binary64 and normal binary32 (or zero).
				 */
				double d = exponent == 0 ? ldexp((double)mantissa, -24) :
				    ldexp(1.0 + (double)mantissa / 1024.0, (int)exponent - 15);
				float f = (float)((h & 0x8000) ? -d : d);
				memcpy(&expected, &f, sizeof(expected));
			}
			float f = _mesa_half_to_float_slow((uint16_t)h);
			memcpy(&actual, &f, sizeof(actual));
			if (actual != expected) {
				if (failures < 4)
					fprintf(stderr, "flush=%u half=%04x got=%08x expected=%08x\n",
					    mode, h, actual, expected);
				failures++;
			}
		}
	}
	set_fp_control(saved);
	printf("65536 encodings in each of two FP modes: %u failures\n", failures);
	return failures != 0;
}
