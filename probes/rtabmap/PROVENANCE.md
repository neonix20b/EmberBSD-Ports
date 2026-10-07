# RTAB-Map source provenance

Checked against primary upstream metadata on 2026-10-07.

- [Generic stable release 0.23.8](https://github.com/introlab/rtabmap/releases/tag/0.23.8),
  pin `d069becc724905d6465a8758c40dae88e13bb9e8`.
- [Tags](https://github.com/introlab/rtabmap/tags) also contain newer
  `0.23.13-{rolling,lyrical,kilted,jazzy,humble}` ROS distribution releases.
  This ROS-free core recipe uses the latest generic stable tag and backports
  the accepted OpenCV 5 change. It does not follow a ROS distribution branch.
- [Checked master](https://github.com/introlab/rtabmap/commit/aa95581cd2f0adca514e0fa6747ea4d7ce53d962)
  had activity on 2026-10-04.
- [Archive](https://codeload.github.com/introlab/rtabmap/tar.gz/d069becc724905d6465a8758c40dae88e13bb9e8):
  SHA256 `587d8936b8d8669b196d500df80e373417e0c4c033309a2e4a0b84a627117284`;
  22,276,030 bytes; extracted source approximately 41 MiB.

## Licensing boundary

The main code is BSD-3-Clause, Mathieu Labbe, IntRoLab/Universite de Sherbrooke
and contributors. The bundled **utilite library is LGPL-3.0-or-later** according
to its file notices; the headless profile still uses it. Therefore this is not
an all-BSD library stack. Original notices and license material are installed.

The private, modified `rtflann` namespace contains BSD-licensed FLANN-derived
code and bundled BSD-2-Clause LZ4 source. It is compiled into RTAB-Map and does
not install another public FLANN/LZ4 provider. Its modified API is distinct
from PCL's external FLANN library; replacing it needs a separate compatibility
and map-database test. Preserve its individual source notices.

Disable optional TORO (noncommercial CC-BY-NC-SA), ORB-OCTREE, Madgwick and
Vertigo (GPL-derived components), together with unused device/GUI/Python
backends. The graph solver is the common GTSAM 4.3.0. Common Eigen 5.0.1,
OpenCV 5.0.0, PCL 1.15.1 and SQLite 3.53.4 keep their own notices and licenses.
Our original shell/C++ probe is MIT; upstream-file patches keep upstream terms.

The unchanged GNU license texts were retrieved on 2026-10-07:

- [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.txt),
  `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`.
- [LGPL-3.0](https://www.gnu.org/licenses/lgpl-3.0.txt),
  `e3a994d82e644b03a792a930f574002658412f62407f5fee083f2555c5f23118`.

## Patches

`opencv5-upstream.patch` selects the core, top-level CMake and installed-config
changes from accepted [PR 1732](https://github.com/introlab/rtabmap/pull/1732),
merge commit `d9f3337f978fffd9cf4b04bee15636bf00a2b870`, author Mathieu Labbe,
merged 2026-07-30. GUI/CI changes and the version bump to 0.23.9 are omitted;
the selected stable version remains 0.23.8. The adaptation handles the
calib3d split, features headers and changed OpenCV camera interfaces.
The original [complete patch](https://github.com/introlab/rtabmap/commit/d9f3337f978fffd9cf4b04bee15636bf00a2b870.patch)
has SHA256 `a5aae59ec0684eef289a0ef514267ca99c5ddd6d7b9fc2a1c62de2504f3d6e22`;
the selected patch is `14785bb1c82d30c7f03e82d6a1fe7d72ab7739d5bf6451feb5d4ef4fef20a24c`.
The upstream acceptance applies to the original change, not this selection.

`shared-headless-dependencies.patch` is local AI-assisted work, not submitted
upstream. It pins common dependency versions, makes SQLite/GTSAM required,
and removes the highgui component from the headless configuration. Unused
highgui includes become imgcodecs; CameraVideo uses videoio. Real `photo`
exposure fusion and stitching exposure compensation remain enabled.
GTSAM's stable 4.3.0 uses `AttitudeFactor<Pose3>`: the version guard changes
from `<=40300` to `<40300`, matching the selected GTSAM header. No missing
API is stubbed. Native compilation and all algorithm tests remain pending.
