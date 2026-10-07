# Ceres Solver source probe

Ceres provides nonlinear least-squares fitting for calibration and estimation.
This probe installs stable Ceres 2.2.0 with the common Eigen 5.0.1, then builds
an independent application using the installed CMake package. EmberBSD Ports
owns the recipe, Eigen compatibility patch and consumer checks.

The AArch64 EmberBSD VM build passed all three installed-consumer checks on
2026-10-07 with GCC 12.5.0. [Native evidence](NATIVE.md) records the numerical
results, runtime linkage, source guards and validation limits.

## Build and test

The target is native EmberBSD/NetBSD with a C++17 compiler, CMake, Ninja, curl,
tar, patch and SHA256 support. `CC` and `CXX` default to the base compilers and
may be overridden as a coherent pair. `JOBS` defaults to 1. Use a fresh absolute
work path whose parent exists; a failed or existing work directory is preserved.

```sh
sh probes/ceres/build.sh /var/tmp/ceres-probe
sh probes/ceres/test.sh /var/tmp/ceres-probe
```

An optional second build argument supplies an absolute archive-cache directory
containing the filenames from [sources.tsv](sources.tsv). Cached files are also
verified. The build installs only inside `WORK/install`; it never installs a
system package. Logs, source hashes, compiler identity and linkage evidence
remain under `WORK/logs`. `test.sh` refuses a stale `WORK/test-build` directory;
preserve or move it before a deliberate rerun.

The release needs no Abseil. Its upstream `MINIGLOG` mode supplies diagnostics.
The CPU profile enables Eigen sparse support and disables external SuiteSparse,
LAPACK, METIS, CUDA, gflags, examples, benchmarks and upstream test builds.
No project-owned or upstream Python step runs in this configuration.
See [PROVENANCE.md](PROVENANCE.md) for source licenses and the local Eigen patch.

## Contract and limits

Three bounded installed-consumer checks cover:

- Nonlinear exponential calibration with 31 observations and two coupled
  unknowns, convergence, a reduced objective, parameter errors below `1e-8`
  and maximum response residual below `1e-8`.
- Invalid solver options, meaningful rejection diagnostics and unchanged state.
- A measurement that cannot evaluate its residual, unsuccessful solution status
  and unchanged parameters.

The consumer requires the installed Ceres and Eigen versions exactly. The
native runner checks the loaded Ceres path and that libstdc++ belongs to the
recorded compiler. Each CTest case has a 20-second outer timeout; the solve
also has a five-second limit. Portable input guards can be checked separately:

```sh
sh probes/ceres/tests/build-guards.sh /var/tmp
```

These reject an existing work path, zero jobs and a corrupt archive before
extraction. This is a source probe, not a pkgsrc package, physical calibration,
a full Ceres upstream suite, GPU validation, or a hard-real-time guarantee.
