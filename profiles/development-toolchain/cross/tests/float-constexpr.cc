// SPDX-License-Identifier: BSD-2-Clause
// Target floating-point constant evaluation exercises the host GMP/MPFR.
#include <cmath>
#include <limits>

constexpr _Float32 float32_max = std::numeric_limits<_Float32>::max();
constexpr long double large_power = __builtin_powl(__LDBL_MAX__, 2.0L / 3.0L);
static_assert(float32_max > 1.0f);
static_assert(large_power > 1.0L && large_power < __LDBL_MAX__);
