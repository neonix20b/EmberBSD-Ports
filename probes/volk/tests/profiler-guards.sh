#!/bin/sh
# SPDX-License-Identifier: MIT
# Test the smoke runner's failure handling, not VOLK's numerical algorithms.
set -eu
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
cmake=${CMAKE:-cmake}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/ember-volk-profiler-guards.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
cat > "$scratch/profiler" <<'EOF'
#!/bin/sh
printf '%s\n' "RUN_VOLK_TESTS: ${EMBER_TEST_KERNEL}(vlen=31)"
printf '%s\n' 'Best aligned arch | generic' 'Best unaligned arch | generic'
printf '%s\n' 'Session summary (1 kernels):'
[ "$EMBER_TEST_ERROR" = no ] || printf '%s\n' 'volk_32f_x2_multiply_32f: fail on arch neon'
exit "$EMBER_TEST_STATUS"
EOF
chmod +x "$scratch/profiler"
export EMBER_TEST_KERNEL=volk_32f_x2_multiply_32f EMBER_TEST_ERROR=no EMBER_TEST_STATUS=0
"$cmake" "-DPROFILER=$scratch/profiler" -P "$recipe/profiler.cmake" > "$scratch/ok.txt" 2>&1
for test in exit-status numerical-failure missing-kernel; do
    EMBER_TEST_KERNEL=volk_32f_x2_multiply_32f EMBER_TEST_ERROR=no EMBER_TEST_STATUS=0
    case "$test" in
        exit-status) EMBER_TEST_STATUS=42 ;;
        numerical-failure) EMBER_TEST_ERROR=yes ;;
        missing-kernel) EMBER_TEST_KERNEL=unrelated_kernel ;;
    esac
    if "$cmake" "-DPROFILER=$scratch/profiler" -P "$recipe/profiler.cmake" > "$scratch/$test.txt" 2>&1; then
        echo "FAIL: profiler wrapper accepted $test" >&2
        exit 1
    fi
    echo "PASS: profiler wrapper rejected $test"
done
echo 'PASS: successful output accepted; all three failure controls rejected.'
