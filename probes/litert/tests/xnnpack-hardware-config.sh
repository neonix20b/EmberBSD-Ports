#!/bin/sh
# SPDX-License-Identifier: MIT
# Build the actual-source contract. Run its output on the compiler's target.
set -eu
if [ "$#" -ne 3 ]; then
  echo "usage: $0 XNNPACK_SOURCE PTHREADPOOL_SOURCE OUTPUT" >&2
  exit 2
fi
xnn_source=$(cd "$1" && pwd)
pool_source=$(cd "$2" && pwd)
output=$3
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$(dirname -- "$output")"
# Conventional compiler flag variables intentionally undergo word splitting.
# XNNPACK_TEST_NETBSD enables only the real dispatcher branch on AArch64 hosts.
# All optional build flags are on to catch confusing compiled and usable ISA.
${CC:-cc} ${CPPFLAGS:-} ${CFLAGS:-} -std=c11 -pthread \
  -DXNNPACK_TEST_NETBSD=1 -DXNN_ENABLE_CPUINFO=0 -DXNN_LOG_LEVEL=0 \
  -DXNN_ENABLE_ARM_FP16_SCALAR=1 -DXNN_ENABLE_ARM_FP16_VECTOR=1 \
  -DXNN_ENABLE_ARM_DOTPROD=1 -DXNN_ENABLE_ARM_BF16=1 \
  -DXNN_ENABLE_ARM_I8MM=1 -DXNN_ENABLE_ARM_SME=1 -DXNN_ENABLE_ARM_SME2=1 \
  -I"$xnn_source" -I"$pool_source/include" \
  "$test_dir/xnnpack-hardware-config.c" \
  "$xnn_source/src/xnnpack/init-once.c" ${LDFLAGS:-} -o "$output"
echo "Built XNNPACK dispatcher contract: $output"
