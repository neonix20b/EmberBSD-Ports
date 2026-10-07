# PCL headless geometry source profile

This profile prepares Point Cloud Library (PCL) 1.15.1 for filtering point clouds
and recovering rigid motion through iterative closest point registration.
PCL owns the algorithms; EmberBSD Ports owns this recipe, the Eigen dependency
adaptation and the installed-consumer checks.

The current state is **source preparation only**. Archive hashes, patch
application and shell input guards have been checked. Native compilation,
installed consumer execution and binary packaging remain unverified.

## Dependencies and build

Use the same Eigen 5.0.1 installation as the other
[robotics foundations](../robotics-foundations/README.md), with a coherent C++17
compiler/runtime. This profile expects pkgsrc Boost 1.91.0, LZ4 1.10.0, CMake,
Ninja, pkg-config, curl and patch under `/usr/pkg`. It does not install a second
Eigen, Boost or OpenCV. OpenCV is not needed by these selected PCL components.

FLANN 1.9.2 is built into the disposable prefix because PCL's kdtree and search
components require it. The optional nanoflann backend does not remove that
requirement in PCL 1.15.1. FLANN is configured for C++ only; its Python, MATLAB,
CUDA, MPI, HDF5, documentation and example features are disabled.

```sh
export PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/usr/sbin:/bin:/sbin
EIGEN_PREFIX=/absolute/common-foundations/install JOBS=1 \
  sh probes/pcl/build.sh /absolute/new-pcl-work /absolute/archive-cache
sh probes/pcl/test.sh /absolute/new-pcl-work
```

The optional cache contains the exact filenames in [sources.tsv](sources.tsv).
Omit it to download from their pinned upstream locations. The builder rejects
an existing work directory and checks every archive before extracting any.
Installations, sources and logs stay under the new work directory.

`JOBS` defaults to one. No address-space limit is imposed by default. An
explicit positive `BUILD_AS_KIB` requests a soft per-process limit inherited
by compiler children; the builder verifies it and preserves the hard limit.
Omit the variable to retain inherited process limits. The effective limit and
job count are recorded in logs. No VM-wide resource setting is changed.

The shared-library profile enables `common`, `kdtree`, `octree`, `search`,
`sample_consensus`, `filters`, `2d`, `features`, `registration`, `io`,
`surface`, `segmentation`, `geometry` and `ml`. The added modules serve the
shared headless RTAB-Map core without another PCL installation. It disables
GUI/VTK/Qt, device I/O, OpenNI, CUDA, OpenMP, PNG, Qhull, applications and tools.
`PCL_ONLY_CORE_POINT_TYPES=ON` limits upstream explicit template instantiations
to the core point types. Other types may require client-side instantiation;
this is not a full all-types PCL binary distribution. Native CPU-specific
instruction selection is disabled.

The separate `test.sh` offers the same optional soft address-space limit
before compiling and running the installed consumer.

FLANN's CMake policy floor is set to 3.5 for current CMake. The local PCL patch
changes both build-time and exported dependency requests to Eigen 5.0.1 exactly.
It preserves Eigen's version policy rather than making Eigen pretend to be 3.x.
See [provenance](PROVENANCE.md) for release commits, licenses and patch status.

## Prepared installed-consumer checks

The tests configure an independent CMake project against the installed PCL,
FLANN and common Eigen. They check exact package versions, imported library
locations and loaded ELF libraries, including the selected C++ runtime.

| Case | Independent expected outcome |
|---|---|
| `filter` | Range filtering removes a distant point and NaN; voxel centroids are `(0.2,0.2,0.2)` and `(1.2,0.2,0.2)` |
| `empty-filter` | An empty input produces empty pass-through and voxel outputs |
| `registration` | ICP recovers a known small rotation/translation and every transformed point within fixed tolerances |
| `no-correspondence` | Distant clouds with a bounded correspondence radius must not report convergence |
| `matrix-check` | The numerical acceptance predicate rejects NaN and both infinities in each matrix coefficient |

Transform acceptance checks all coefficients, including the homogeneous bottom
row, for finiteness. A host regression reproduces the false pass possible with
Eigen's default `maxCoeff()` NaN behavior and verifies the explicit finite check.

`sh probes/pcl/tests/build-guards.sh /absolute/scratch-parent` checks existing
work preservation, invalid job/limit values and rejection of damaged archives without
compiling. Passing these guards does not establish native PCL support.

These software fixtures do not validate a physical depth camera/LiDAR, sensor
calibration, segmentation, visualization, real-time deadlines or sustained
operation on a board. The profile is not yet an installable pkgsrc package.
