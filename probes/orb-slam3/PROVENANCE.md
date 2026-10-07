# ORB-SLAM3 source provenance

The selected upstream release is
[v1.0-release](https://github.com/UZ-SLAMLab/ORB_SLAM3/releases/tag/v1.0-release),
published on 2021-12-22 and still the latest official stable release checked
on 2026-10-07. The tag resolves to
`0df83dde1c85c7ab91a0d47de7a29685d046f637`.
[sources.tsv](sources.tsv) pins its original archive and SHA256.
The old release date does not select old external dependencies: this profile
requires the common OpenCV 5.0.0 and Eigen 5.0.1 installations.

ORB-SLAM3 is GPL-3.0-or-later software by Carlos Campos, Richard Elvira,
Juan J. Gomez Rodriguez, Jose M. M. Montiel and Juan D. Tardos, University of
Zaragoza. Its original ORB-SLAM2 attribution is retained. Upstream's
`Dependencies.md` identifies additional borrowed code and its origins.
All original source notices remain unchanged.

The tag contains modified DBoW2, DLib/DUtils and g2o implementations, plus
Sophus 1.1.0 headers. They are part of the pinned ORB source and are installed
under its private include/library namespace. They do not replace or install
generic system DBoW2, g2o or Sophus packages. g2o carries BSD-2-Clause terms;
Sophus carries MIT terms. Upstream's modified internal interfaces require
these copies; replacing them with shared current libraries is not validated.
They can be removed from this profile when upstream-compatible shared versions
pass its SLAM consumer checks.

The ORB tag's DBoW2/DUtils files refer to an absent `LICENSE.txt`. This profile
retrieves the complete original author notices from pinned DBoW2 and DLib
revisions listed in `sources.tsv`, without replacing their source code.
Both notices have BSD-style redistribution terms including notification of
the original author. They must not be labelled ordinary BSD-2-Clause or
BSD-3-Clause. This profile publishes recipes and patches, not third-party
source or binary distributions. Complete notices are installed alongside
the GPL, g2o and Sophus licenses.

`patches/headless-modern-dependencies.patch` is an AI-assisted local EmberBSD
adaptation, not submitted or accepted upstream. It adds an explicit headless
compilation path, rejects viewer requests, updates OpenCV feature headers,
and includes the explicit OpenCV 5 geometry/stereo headers instead of relying
on former umbrella-header declarations. The common stereo library is reused.
It also repairs worker ownership/shutdown. A canceled global bundle adjustment
worker is joined outside its mutex before reuse; shutdown joins mapping,
loop closing and the remaining GBA worker. LocalMapping uses consistent
lock order during finish/release. The changes retain their source licenses.

The GBA stop flag is atomic through new atomic-reference Optimizer overloads
and an atomic stop setter in the private g2o optimizer. Existing `bool*` APIs
remain available; `NULL` calls are unambiguous. Common templated method bodies
avoid maintaining different numerical implementations. The real g2o iteration
loop is tested with a controlled solver fixture and cancellation from another
thread. Other upstream stop flags are unchanged and are outside this fix.

The GBA generation counter is an unsigned integer rather than the upstream
`bool`: increments must represent successive generations and C++17 rejects
`bool++`. Upstream [issue 550](https://github.com/UZ-SLAMLab/ORB_SLAM3/issues/550)
documents the same failure; the checked upstream default-branch header still
has the boolean declaration. A consumer regression checks three increments.
Worker creation captures the generation under its mutex and passes it by value.
Loop correction joins the previous GBA before its LocalMapping stop request,
so the finishing GBA cannot clear that request through `Release()`.
These two races were inherited from upstream. The initial adaptation also
introduced a viewer self-join outside the headless profile; the join helper
now detects the calling thread, with a regression independent of GUI libraries.
GCC-private `stdint-gcc.h` includes become standard `stdint.h`. Map thumbnail
storage uses the equivalent `unsigned char` without importing OpenGL types.

A full RGB-D repeat exposed an inherited trajectory-history defect. In the
missing-pose branch, upstream repeated the preceding timestamp and marked the
frame as not lost, because its outer state was `OK` or `RECENTLY_LOST`.
The actual branch now calls `AppendUnavailableFrame`, which retains aligned
history lists, records the current timestamp and marks that unavailable pose
lost. Its source license is retained. A mutation regression restores both
old operations and must fail; the installed production helper must pass.
The original failed run also had only 487/573 successfully tracked frames;
fixing export does not retroactively accept that tracking result.

The original native source lists are built through an installation wrapper
with C++17 and without host-specific `-march=native`. This is needed for
current dependencies and relocatable installed headers/CMake targets.
The original translation units are preserved and built with ordinary `-O2`.
The recipe does not impose memory limits or GCC garbage-collection tuning.
Python evaluation scripts, ROS, camera examples and duplicated TUM-IMU
evaluation data are not built. No fake Pangolin API or algorithm stub is used.

Selective extraction retains `src`, `include`, `Thirdparty`, `Vocabulary`,
`Examples/RGB-D`, `LICENSE`, `Dependencies.md`, `README.md`, `Changelog.md`
and the original top-level `CMakeLists.txt`. The downloaded archive and hash
are unchanged. Other example trees and `evaluation` contain unused datasets
or tools and are omitted from the private build tree.

The wrapper, scripts and independent C++ contracts are original AI-assisted
EmberBSD work under [LICENSE](LICENSE). Installation and synthetic API checks
alone do not validate a SLAM trajectory, sensor driver or live camera.
