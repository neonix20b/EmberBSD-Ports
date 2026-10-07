/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 EmberBSD contributors */
#include <stdint.h>
#ifdef __cplusplus
#include <cmath>
#endif
#include <volk/volk_common.h>
#include <stdio.h>
#ifdef __cplusplus
#define CHECK_NAN(x) std::isnan(x)
#else
#define CHECK_NAN(x) isnan(x)
#endif

static unsigned checked;

static int check(int condition, const char *message)
{
    ++checked;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        return 1;
    }
    return 0;
}

int main(void)
{
    int errors = 0;
    const float pi = 0x1.921fb6p1f;
    const float half_pi = pi / 2.0f;
    errors += check(log2f_non_ieee(1.0f) == 0.0f, "log2(1)");
    errors += check(log2f_non_ieee(8.0f) == 3.0f, "log2(8)");
    errors += check(log2f_non_ieee(0.0f) == -127.0f, "log2(0) clamps");
    errors += check(log2f_non_ieee(INFINITY) == 127.0f, "log2(inf) clamps");
    errors += check(CHECK_NAN(log2f_non_ieee(NAN)), "log2(NaN)");
    errors += check(CHECK_NAN(log2f_non_ieee(-1.0f)), "log2(negative)");
    errors += check(CHECK_NAN(volk_arctan(NAN)), "atan(NaN)");
    errors += check(volk_arctan(INFINITY) == half_pi, "atan(+inf)");
    errors += check(volk_arctan(-INFINITY) == -half_pi, "atan(-inf)");
    errors += check(CHECK_NAN(volk_atan2(NAN, 1.0f)), "atan2(NaN, finite)");
    errors += check(CHECK_NAN(volk_atan2(1.0f, NAN)), "atan2(finite, NaN)");
    errors += check(volk_atan2(INFINITY, INFINITY) == pi / 4.0f, "atan2(+inf, +inf)");
    errors += check(volk_atan2(-INFINITY, INFINITY) == -pi / 4.0f, "atan2(-inf, +inf)");
    errors += check(volk_atan2(INFINITY, -INFINITY) == 3.0f * pi / 4.0f,
                    "atan2(+inf, -inf)");
    errors += check(volk_atan2(-INFINITY, -INFINITY) == -3.0f * pi / 4.0f,
                    "atan2(-inf, -inf)");
    errors += check(volk_atan2(INFINITY, 1.0f) == half_pi, "atan2(+inf, finite)");
    errors += check(volk_atan2(1.0f, -INFINITY) == pi, "atan2(finite, -inf)");
    errors += check(volk_atan2(-1.0f, -INFINITY) == -pi, "atan2(negative, -inf)");
    printf("math header special values: %u checks, %d errors\n", checked, errors);
    return errors ? 1 : 0;
}
