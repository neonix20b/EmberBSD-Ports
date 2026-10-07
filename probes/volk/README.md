# VOLK 3.3.0 source profile

This profile builds an installed VOLK shared library for vector DSP on native
NetBSD/aarch64. It also installs the current fmt 12.2.0 shared dependency for
the upstream profiler and reuse by other consumers. EmberBSD Ports owns the
source pins, build helper and installed-library contracts. Compatibility patches
come unchanged from NetBSD pkgsrc, with its original identifiers and attribution.
This is a source probe, not a pkgsrc package or a physical radio validation.

## Build and test

Use C/C++ compilers with C++17 support, CMake 3.22 or newer, Ninja, tar, patch,
SHA256 and an existing Python 3 interpreter with Mako and MarkupSafe. The helper
does not install packages or change the common toolchain. Python is an upstream
build requirement; the installed library and C++ contracts do not use it.

```sh
export CC=/usr/bin/cc CXX=/usr/bin/c++
export PATH=/usr/pkg/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PYTHON_EXECUTABLE=/usr/pkg/bin/python3.13
JOBS=1 ./build.sh /absolute/new/volk-work
./test.sh /absolute/new/volk-work
```

For an offline build, pass a directory containing both files from
[sources.tsv](sources.tsv) as the second argument to `build.sh`. Every SHA256
is checked before extraction. The work directory must be new. Build and test
logs remain in `WORK/logs`; the reusable prefix is `WORK/install`.
Set `CMAKE` and `CTEST` if the common tools are outside PATH.

Consumers can use `find_package(Volk 3.3.0 EXACT CONFIG REQUIRED)` and link
`Volk::volk` with `CMAKE_PREFIX_PATH=WORK/install`. fmt provides `fmt::fmt`
from the same prefix. The contract verifies installed exports and dynamic linkage.

## Numerical and dispatch checks

The installed C++ executable tests dot product, elementwise multiplication and
complex magnitude against independent double-precision scalar expected values.
Each operation runs with ordinary dispatch and `VOLK_GENERIC=1`, and manually
exercises every advertised implementation. It requires generic and NEON kernels.
Tests cover 22 lengths from zero to 1023, vector-width boundaries and tails,
aligned and offset pointers, untouched inputs and output guard regions.

Dot product uses relative/absolute tolerance `2e-5`; multiplication and normal
magnitude use `2e-6`. Upstream's older `neon` magnitude approximation is checked
at `5e-3`, and `neon_fancy_sweet` at `1.5e-2`. These deliberately approximate
implementations are tested separately. Default neonv8 and forced generic
magnitude dispatch must meet the stricter `2e-6` bound.

Two installed-header regressions compile the same finite/NaN/infinity contract
as C17 and C++17, with 18 checks each. The original header fails after `<cmath>`
is included; the retained pkgsrc fix passes. A short installed profiler run tests
fmt integration with `--dry-run`, without saving machine preferences. These
nine CTest cases do not constitute a throughput benchmark.

Baseline ARMv8 NEON is selected through upstream's supported configuration.
cpu_features is disabled because it lacks a NetBSD AArch64 backend. The build
requires precisely the generic, neon and neonv8 machines, and tests require
actual neonv8 selection and 16-byte alignment. See [provenance](PROVENANCE.md).
Optional ISA detection, x86 dispatch, benchmark speed, physical boards and
long-running radio/stream workloads are outside this profile's validation.

## Verified result

On 2026-10-07, all nine installed tests passed in an EmberBSD/NetBSD 11 AArch64
VM with base GCC 12.5.0, CMake 4.3.3 and Ninja 1.13.2. The six DSP tests execute
1,144 kernel/length/alignment cases in total. Both header contracts pass all 18
special-value checks, and the installed profiler successfully formats and tests
its selected kernel with shared fmt 12.2.0. Default dispatch selects neonv8;
manual generic, neon, neonv8 and the approximate NEON magnitude kernel execute.

The profiler smoke wrapper requires a successful exit and completed kernel
output, and rejects reported failures even if upstream exits zero. Run
`sh probes/volk/tests/profiler-guards.sh` to check its error handling:
matched output with exit 42, a numerical failure with exit zero and a missing
selected kernel must all fail. These runner controls are separate from the
nine installed library/application cases.

ELF inspection confirms 64-bit AArch64 NetBSD binaries. Dynamic linkage resolves
VOLK and fmt within the selected prefix, and base `/usr/lib/libstdc++.so.9`
and `/usr/lib/libgcc_s.so.1`. Build generation reused the image's Python 3.13.14,
Mako 1.3.12 and MarkupSafe 3.0.3. These existing host tools are recorded, not
installed or upgraded by this probe; it does not claim validation with the
separate common Python 3.14 source recipe. No physical board was tested.
