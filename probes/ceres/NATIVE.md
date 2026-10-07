# Native Ceres validation

Validated on 2026-10-07 in an AArch64 EmberBSD VM: NetBSD 11.0 userland,
`EMBER64` kernel, one virtual CPU, 3 GiB RAM, GCC/G++ 12.5.0, CMake 4.3.3,
Ninja 1.13.2. This is VM evidence, not a board or hardware calibration result.

The pinned Ceres 2.2.0 and Eigen 5.0.1 archives were verified before extraction.
The local Eigen dependency-request patch was applied, and the complete selected
CPU profile compiled and installed with `JOBS=1`. Schur specializations remain
enabled. All three independent installed-consumer checks passed in 0.01 seconds.

| Check | Result |
|---|---|
| Exponential calibration, 31 observations | Converged to slope `0.3` and intercept `0.1` |
| Largest response residual | `6.66134e-16`, below `1e-8` |
| Final least-squares objective | `2.21867e-30`, below `1e-16` |
| Invalid solver iteration limit | Rejected with diagnostics; parameters unchanged |
| Unavailable residual evaluation | Unusable failed solution; parameter unchanged |
| Installed library discovery | CMake selected the exact installed Ceres/Eigen versions |
| Runtime linkage | Installed `libceres.so.4` and base `/usr/lib/libstdc++.so.9`; compiler-runtime identity matched |
| Build input guards | Existing work, zero jobs and corrupt cached archive rejected before extraction |

SHA256 of the installed shared library was
`f566db227632c9cdf6c142780941e5d00a864d7c5384481bc8fc1cfdbc01159f`.
The installed-consumer executable was
`7b125571bf4c9aadffd20103ae0d5f66ab31ad4b8c79d90707164fd238e73387`.
These identify this validation build; they are not a bit-for-bit reproducibility
claim across different toolchains or work paths.

An earlier Apple Clang 21 host build also passed the three consumers. The old
Eigen 3.3 CMake request was separately rejected by the installed Eigen 5.0.1
package, confirming why the profile patch is required.

The checks cover CPU dense nonlinear estimation and error handling. They do
not cover the full upstream suite, large sparse calibration workloads,
SuiteSparse/LAPACK, CUDA, physical sensors, other boards or long-duration runs.
Source identities, licenses and patch status are in [PROVENANCE.md](PROVENANCE.md).
