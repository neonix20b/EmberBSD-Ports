/* SPDX-License-Identifier: MIT */
/* Exercise the actual XNNPACK dispatcher, without a cpuinfo substitute. */
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "src/xnnpack/hardware-config.h"
#include "src/xnnpack/init-once.h"
#include "src/xnnpack/log.h"

#if !XNN_ARCH_ARM64
#error This contract requires an AArch64 compiler.
#endif
#if XNN_ENABLE_CPUINFO
#error This contract checks the NetBSD path without cpuinfo.
#endif

/* Select only the dispatcher branch on an AArch64 host. System headers above
 * keep their real host definitions. A native NetBSD build needs no override.
 */
#if defined(XNNPACK_TEST_NETBSD) && !defined(__NetBSD__)
#define __NetBSD__ 1
#endif
#if !defined(__NetBSD__)
#error Use NetBSD or explicitly select XNNPACK_TEST_NETBSD for the host contract.
#endif
#include "src/configs/hardware-config.c"

static void check(int condition, const char *message) {
  if (!condition) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(EXIT_FAILURE);
  }
}

int main(void) {
  const struct xnn_hardware_config *config = xnn_init_hardware_config();
  const uint64_t baseline = xnn_arch_arm_vfpv3 | xnn_arch_arm_neon |
      xnn_arch_arm_neon_fp16 | xnn_arch_arm_neon_fma | xnn_arch_arm_neon_v8;
  check(config != NULL, "hardware initialization must succeed without cpuinfo");
  check((config->arch_flags & baseline) == baseline,
        "AArch64 baseline NEON, conversion and FMA must be available");
  check(config->arch_flags == baseline,
        "optional CPU extensions must not be inferred from build flags");
  check(!xnn_is_f16_supported_natively(config) &&
        !xnn_is_f16_compatible_config(config),
        "FP16 conversion must not enable FP16 arithmetic dispatch");
  check(config->l1_data_cache_bytes == 0 && config->l2_data_cache_bytes == 0,
        "unknown cache sizes must not be fabricated");
  for (size_t i = 0; i < XNN_MAX_UARCH_TYPES; ++i) {
    check(config->uarch[i] == xnn_uarch_unknown,
          "unknown microarchitecture must retain generic dispatch");
  }
  check(xnn_init_hardware_config() == config,
        "repeated initialization must reuse the real initialization guard");
  struct xnn_hardware_config override = *config;
  override.arch_flags = 0;
  xnn_set_hardware_config(&override);
  check(xnn_init_hardware_config()->arch_flags == 0,
        "upstream test override must remain available");
  xnn_reset_hardware_config();
  check(xnn_init_hardware_config()->arch_flags == baseline,
        "reset must restore conservative hardware detection");
  printf("PASS: NetBSD AArch64 XNNPACK dispatch, flags=0x%" PRIx64 "\n", baseline);
  return EXIT_SUCCESS;
}
