# PCL source profile provenance

Official releases, tags and source contents were checked on 2026-10-07.

| Source | Exact commit | License |
|---|---|---|
| [PCL 1.15.1](https://github.com/PointCloudLibrary/pcl/releases/tag/pcl-1.15.1) | `3346843ea6b97697a1577293aa9cdf236b5c7ffb` | BSD-3-Clause, upstream `LICENSE.txt` and individual notices; Willow Garage, Open Perception and contributors |
| [FLANN 1.9.2](https://github.com/flann-lib/flann/tree/1.9.2) | `c50f296b0b27e14667d272b37acc63f949b305c4` | BSD-3-Clause, upstream `COPYING`; Marius Muja and David G. Lowe |

These were the current stable tagged releases when checked. The age of FLANN's
release does not select an older version: 1.9.2 is the latest upstream tag.
[sources.tsv](sources.tsv) fixes commit-addressed archive URLs and SHA256 hashes.
The downloaded archives are 68,706,780 bytes (PCL) and 34,642,850 bytes (FLANN).
Their original trees occupy approximately 139 MiB and 80 MiB respectively on
the source preparation host. Build space has not been measured.

The profile consumes the common Eigen 5.0.1 (MPL-2.0 with upstream per-file
exceptions), pkgsrc Boost 1.91.0 (BSL-1.0), and LZ4 1.10.0 (upstream BSD/GPL
license split). It links LZ4's library; it does not incorporate the LZ4 CLI.
Their original sources and license inventories belong to those providers.
The builder copies PCL and FLANN's top-level license files into the disposable
installation and retains the original source notices.

## Local adaptation

The common headless profile also enables `io`, `surface`, `segmentation` and
their `geometry`/`ml` dependencies for RTAB-Map core. These are modules of the
same PCL installation. Qhull, VTK, device backends and visualization stay off;
RTAB-Map's selected surface code does not require convex/concave hull APIs.
The expanded profile has not yet been compiled natively.

`patches/pcl-eigen5.patch` changes PCL's top-level `find_package(Eigen3 3.3)`
and the same request in `PCLConfig.cmake.in` to exact Eigen 5.0.1. Eigen 5's
CMake version file rejects the 3.3 request. Updating the export is necessary
for independent installed consumers too. No Eigen algorithm or package-version
metadata is changed. This local EmberBSD profile patch was written with AI
assistance; it has not been submitted or accepted upstream.

FLANN is unchanged. The builder passes `CMAKE_POLICY_VERSION_MINIMUM=3.5`
because its original CMake minimum is 2.6 and current CMake no longer accepts
compatibility below 3.5. Native configuration remains to be verified.

The recipe and consumer checks are MIT licensed under [LICENSE](LICENSE),
with AI assistance disclosed. They do not relicense upstream source.
