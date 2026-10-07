# RTAB-Map headless core source probe

Prepare **RTAB-Map 0.23.8** for an installed core mapping/localization scenario
on the common Eigen 5.0.1, OpenCV 5.0.0, PCL 1.15.1, GTSAM 4.3.0 and SQLite
3.53.4 stack. Qt and ROS are optional upstream; this profile enables neither.
See [source provenance](PROVENANCE.md), [pin/hash](sources.tsv) and [license](LICENSE).
The bundled utilite component remains LGPL-3.0-or-later.

**Source preparation only.** Source hashes, selected patch application and
portable input guards passed on the host. Native configuration, compilation,
installed consumer execution and numeric acceptance are not established.
This directory must not be presented as a working mapping port yet.

## Common dependencies and build

Use the expanded [media OpenCV provider](../media/README.md), including `video`,
`stitching`, `photo` and `videoio`, with working PNG and JPEG codecs. RTAB-Map
uses those codecs for map storage and reopening. The common [PCL](../pcl/README.md)
profile includes `io`, `surface`, `segmentation` and their dependencies.
GTSAM is the selected graph optimizer; TORO, GPL-derived optional algorithms,
OpenMP, hardware backends, Python, GUI applications and tools are disabled.

```sh
EIGEN_PREFIX=/absolute/foundations/install \
OPENCV_PREFIX=/absolute/media/install \
PCL_PREFIX=/absolute/pcl/install \
GTSAM_PREFIX=/absolute/gtsam/install \
SQLITE_PREFIX=/absolute/sqlite/install \
JOBS=1 sh probes/rtabmap/build.sh /absolute/new-rtabmap-work /absolute/archive-cache
sh probes/rtabmap/test.sh /absolute/new-rtabmap-work
```

Use `/usr/pkg` for a dependency only when it provides the exact selected
version; a stale system SQLite is not accepted. Reuse existing source recipes
when a previous private installation has been removed. No older parallel
library stack is introduced. Native C++17, CMake, Ninja, patch, curl, tar and
SHA256 tools are required. The archive cache argument is optional.

The builder refuses an existing work path, verifies archives before extraction
and records dependency prefixes. `JOBS=1` is the default. No address-space
limit is imposed by default. An explicit positive `BUILD_AS_KIB` requests a
verified soft limit; inherited hard limits and VM-wide settings stay unchanged.
Failed builds retain their logs. Do not present old files as new build output.
The recipe retains CMake's normal Release optimization flags.

## Prepared installed contract

The C++ consumer generates six analytic RGB-D views and explicit, deterministic
feature identities/descriptors. It uses the real core vocabulary, registration,
graph optimization and SQLite persistence APIs. The map is closed and reopened
for localization; JPEG RGB and 16-bit PNG depth must decode correctly. A known
view must recover its 20 cm world position despite a 25 cm odometry error.
An empty observation must fail, and read-only localization must not add nodes.
World points, camera projections and expected positions are independent of
RTAB-Map's solver and registration implementation.

This isolates core mapping from image feature detection; it is not a camera
front-end benchmark. Numeric limits are prospective until the native run.
The installed consumer has a 180-second deadline and checks actual library
and C++ runtime linkage. GUI, sensor capture, loop closure on real scenes,
all optional optimizers and long-running map growth remain outside this scope.
