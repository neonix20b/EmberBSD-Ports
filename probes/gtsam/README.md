# GTSAM factor-graph source profile

GTSAM 4.3.0 provides a C++17 library for combining measurements and motion
constraints into a state estimate. This source profile prepares a CPU build
and independent installed-consumer checks for scalar sensor fusion and a
nonlinear planar pose graph. GTSAM owns the algorithms and Ports owns this
recipe and its validation fixtures.

The current state is **an incomplete native build**. Archive hashes, shell
input guards and native configuration have been checked. On 2026-10-07,
the AArch64 NetBSD 11/EMBER64 build with GCC 12.5.0, Eigen 5.0.1 and `JOBS=2`
was interrupted when the user closed the work scope. Ninja reported 217 of
259 steps before the interrupt; the recorded exit status is 130. This was
not a compiler failure. No library installation, installed-consumer run or
binary package was completed. The profile is not yet a working native port.

## Dependencies and build

Use the existing common Eigen 5.0.1 from
[robotics foundations](../robotics-foundations/README.md). GTSAM's bundled Eigen
is explicitly disabled. The profile requires CMake, Ninja, curl, a C++17
compiler and its matching runtime. It installs only into a new work directory.

```sh
export PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/usr/sbin:/bin:/sbin
EIGEN_PREFIX=/absolute/common-foundations/install JOBS=1 \
  sh probes/gtsam/build.sh /absolute/new-gtsam-work /absolute/archive-cache
sh probes/gtsam/test.sh /absolute/new-gtsam-work
```

The optional cache contains the filename in [sources.tsv](sources.tsv).
Omit it to download from the pinned upstream location. All archives are
verified before extraction; an existing work directory is rejected.

`JOBS` defaults to one. No address-space limit is imposed by default. An
explicit positive `BUILD_AS_KIB` requests a soft per-process limit inherited
by compiler children; the builder verifies it and preserves the hard limit.
Omit the variable to retain inherited process limits. The same optional control
is available in `test.sh`. No VM-wide resource setting is changed.

The profile builds the stable shared C++ library and retains GTSAM's default
matrix rotation and tangent IMU-preintegration choices. Optional Boost features
and serialization, TBB, MKL, CUDA, GeographicLib, CHOLMOD and METIS nested
dissection are disabled. Python/MATLAB wrappers, unstable modules, upstream
examples, timings and tests are disabled. This selected configuration has no
Python build or runtime requirement. The broader upstream project includes
Python-based wrappers, documentation and workflows.

The library still compiles its stable modules, including navigation and
structure from motion. Enabling a module is not validation of all its APIs.
Upstream's internal CCOLAMD, SuiteSparse_config, Spectra and Cephes remain
included; [provenance](PROVENANCE.md) identifies them and their licenses.
This does not add a second public Eigen, Boost or SuiteSparse installation.
A future shared CCOLAMD/Spectra provider should be selected through upstream's
system-provider options and tested with its other consumers.

## Prepared installed-consumer checks

A fresh external CMake project requires GTSAM 4.3.0 and Eigen 5.0.1 exactly.
The test helper checks the loaded installed library and matching C++ runtime.

| Case | Independent expected outcome |
|---|---|
| `linear-fusion` | Three unit-variance measurements yield states `1/3` and `8/3`, with residual cost `1/6` |
| `pose-graph` | A prior, two motions and a loop constraint recover three known poses and anchor covariance `0.01 I` |
| `underconstrained` | A graph containing only one relative measurement reports an indeterminate linear system |
| `missing-state` | A nonlinear factor referencing a missing pose rejects incomplete initial values |
| `matrix-check` | The numerical acceptance predicate rejects NaN and both infinities in each matrix coefficient |

Covariance acceptance checks all coefficients for finiteness before comparing
errors. A host regression reproduces the false pass possible with Eigen's
default `maxCoeff()` NaN behavior and verifies the explicit finite check.

`sh probes/gtsam/tests/build-guards.sh /absolute/scratch-parent` validates
existing work preservation, invalid job/limit values and corrupt archive rejection.
These source-only checks do not establish a successful GTSAM build.

Synthetic graphs do not validate real IMU/GNSS data, visual odometry, map
relocalization, real-time deadlines, a physical board or sustained operation.
This is a source probe, not a released pkgsrc package or a complete navigation
application.
