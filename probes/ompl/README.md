# OMPL 2.0.2 headless source profile

This prepared profile supplies a shared C++ motion-planning library and a
bounded two-dimensional planning contract. EmberBSD Ports owns the recipe
and checks. It does not establish robot collision safety, path optimality,
hardware acceleration or a validated NetBSD package.

The build requires the common Eigen 5.0.1 installation and Boost 1.91.0
serialization/program_options libraries. Both versions are checked exactly.
VAMP, Python bindings, demos, upstream tests and optional Triangle, FLANN,
Spot and yaml-cpp dependencies are disabled. The library and tests need no
Python. Upstream's installed benchmark-statistics script is retained but unused;
running that optional script would require Python separately.

## Build and test on NetBSD

```sh
export PATH=/usr/pkg/bin:/usr/bin:/bin:/usr/sbin:/sbin
export CC=/usr/bin/cc CXX=/usr/bin/c++
export EIGEN_PREFIX=/absolute/common-eigen-prefix
export BOOST_PREFIX=/usr/pkg
JOBS=1 ./build.sh /absolute/new/ompl-work /absolute/cache
./test.sh /absolute/new/ompl-work
```

The optional cache contains the official 2.0.2 release archive pinned in
[sources.tsv](sources.tsv). It includes upstream submodules and is about
142 MiB compressed. CMake, Ninja, tar, SHA256 and C++17 are required.
The helper verifies the archive before extraction and requires a new work
directory. CMake dependency fetching is disconnected; the shared dependencies
must already be installed. No package or toolchain is changed globally.

`JOBS` controls build concurrency; select it for the available builder. The
helpers impose no additional memory ceiling by default. Set `BUILD_AS_KIB`
explicitly only when a soft per-process limit is wanted; the hard limit is
preserved. Logs and installation
remain below work.

An installed C++ consumer uses
`find_package(ompl 2.0.2 EXACT CONFIG REQUIRED)` and links `ompl::ompl`.
The prepared contracts use a fixed seed and bounded iteration count:

- RRTConnect routes from (0.1, 0.5) to (0.9, 0.5) around a closed rectangular
  obstacle in the unit square.
- A separate analytic segment/rectangle validator checks every complete path
  edge, finite bounds, endpoints and length. It does not reuse OMPL's sampled
  motion checker. Tangency counts as collision.
- A goal inside the obstacle must be rejected. A wall joining opposite domain
  boundaries must never produce an exact path. An approximate result remains
  explicitly approximate and is checked for collision as well.
- The geometry checker has direct crossing, tangent, reverse and degenerate
  cases. ELF checks require the selected prefix and base C++ ABI.

CTest enforces exit status and per-case timeouts. A fixed seed makes the chosen
random sequence reproducible; it is not a guarantee of identical paths across
compiler/library versions. Failure within a budget does not prove general
planning infeasibility. The closed wall case is infeasible by its geometry.
`tests/source-guards.sh /absolute/new/guard-work` checks archive rejection and
work preservation on the target, with `EIGEN_PREFIX` set as for the build.

## Current validation

On 2026-10-07, the standalone continuous geometry checker compiled and passed
on macOS ARM64. Shell syntax and source hashes were checked. The full consumer
syntax check stops at missing host Boost headers; no older Boost was used.
**OMPL build, installed contracts and native NetBSD validation are pending.**
The VM was not changed during this preparation. See [provenance](PROVENANCE.md).
