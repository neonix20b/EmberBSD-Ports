# OSQP 1.0.0 source profile

This prepared profile supplies a shared C quadratic-programming solver with
the current QDLDL 0.1.9 direct backend. It is intended for bounded control and
optimization experiments. EmberBSD Ports owns the recipe and consumer checks.
It is not a validated NetBSD package or a real-time control claim.

The configuration uses double precision and 64-bit indices, with timing and
interrupt handling enabled. Code generation, derivatives, language bindings,
upstream demos and upstream tests are outside this profile. QDLDL is compiled
as an object dependency inside libosqp. No older parallel QDLDL is fetched.

## Build and test on NetBSD

```sh
export PATH=/usr/pkg/bin:/usr/bin:/bin:/usr/sbin:/sbin
export CC=/usr/bin/cc CXX=/usr/bin/c++
JOBS=1 ./build.sh /absolute/new/osqp-work /absolute/cache
./test.sh /absolute/new/osqp-work
```

The optional cache contains both [pinned archives](sources.tsv). Without it,
the helper downloads those exact sources. It verifies archives and the patch
before extraction. Work must be a new absolute path. CMake, Ninja, tar, patch,
SHA256 and the base C/C++ compilers are required. Network-free configuration
uses the extracted QDLDL source and disconnected FetchContent.

No additional memory ceiling is imposed by default. Set `BUILD_AS_KIB` explicitly
only when a soft per-process address-space limit is wanted; the hard limit is
preserved. `JOBS` controls build concurrency; select it for the available builder.
Sources, logs
and the installed prefix stay under work. Archive timestamps are ignored when
extracting to avoid regeneration loops with differing host and VM clocks.

An installed consumer uses `find_package(osqp 1.0.0 EXACT CONFIG REQUIRED)`
and links `osqp::osqp`. The test suite checks:

- Analytic two-variable QP optima, independent KKT stationarity,
  complementarity, finite bounds, objective and timing.
- Linear-cost update and warm start, then Hessian/bound updates with separate
  analytic optima.
- A valid but infeasible problem, its status and an independently verified
  primal infeasibility certificate.
- The upstream POSIX listener receiving SIGINT and restoring the previous
  handler. This separate regression intentionally checks private listener
  symbols; the numerical consumer uses the installed public API.

The NetBSD patch selects that existing listener rather than pretending the
platform is Linux. The `tests/source-selection` CMake fixture demonstrates the
original and patched NetBSD source-list behavior without compiling for NetBSD.
`tests/source-guards.sh` checks corrupt-archive rejection and work preservation
on the target host. CTest exit statuses and timeouts are authoritative.

## Current validation

On 2026-10-07, OSQP and QDLDL built on macOS ARM64 with Apple Clang and all
three installed tests passed. The NetBSD source-selection fixture failed with
the original source and passed with the patch. **Native NetBSD build, link
regression and runtime validation are pending.** These host checks establish
API compatibility, not target support or long-running control reliability.
See [provenance](PROVENANCE.md) for licenses, authorship and exact revisions.
