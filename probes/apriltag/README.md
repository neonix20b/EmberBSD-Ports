# AprilTag source probe

Detect fiducial IDs and estimate their pose using the AprilTag 3.4.5 C library.
This Ports-owned source probe provides installed C headers, a shared library
and a standalone numerical contract. No camera or OpenCV is needed for this
workflow. It is not an installable pkgsrc package or calibrated robot vision stack.

## Build and test

Use a C99 compiler, CMake 3.16 or newer, Ninja, tar, patch and `sha256`
(or `shasum`). curl is needed unless an archive cache is supplied.

```sh
JOBS=1 sh probes/apriltag/build.sh /var/tmp/ember-apriltag
sh probes/apriltag/test.sh /var/tmp/ember-apriltag
sh probes/apriltag/tests/build-guards.sh
```

The build path must be absolute and absent. An optional second argument names
an absolute directory containing the archive from [sources.tsv](sources.tsv).
Hashes are checked before extraction. Sources, build products, installation
and logs stay under the selected work path. The recipe enables the shared C
library and disables optional Python bindings and OpenCV/camera examples.
There is no Python build or runtime dependency for this configuration.

The installed upstream `apriltag::apriltag` CMake target is used by an independent
[consumer](tests/contract.c). [CMake discovery](tests/CMakeLists.txt) requires the
exact version in the selected prefix; the runtime linkage check rejects a
library from elsewhere. No source build target is used by the contract.

## Contract and limits

The test creates tag36h11 ID 42 and renders it on a 640 by 480 grayscale image.
It verifies the ID without bit correction, family, decision margin, and center
within 1.5 pixels. It repeats detection after translation, a 0.29-radian rotation
and a scale change. Both cases estimate pose from known camera intrinsics and a
0.16 m tag. Translation must be within 5 mm, each rotation-matrix element within
0.04, and the reported object-space error below `1e-5`. Expectations come from
our independent image transform, not the returned homography. A blank frame
and a black square with invalid code must produce no detections.

A separate installed regression checks ASCII case comparison, trimming and
option parsing for every high byte from 128 through 255, plus a negative
numeric argument. The small [ctype patch](patches/ctype-unsigned-char.patch)
passes unsigned-byte values to ctype macros, fixing native strict compilation
and avoiding signed-char arguments outside the C API domain. Strict warnings
remain enabled. Tests use explicit checks in Release builds and CTest timeouts.

Build guards reject an existing work directory, relative path, invalid `JOBS`
and a corrupt archive before extraction. No test requires invalid pointers or
inconsistent image dimensions, which the upstream C API does not promise to accept.

## Validation

On 2026-10-07 the patched source build and both installed contracts passed on
EmberBSD AArch64 in an isolated VM: EMBER64 kernel `b4f718d`, NetBSD 11.0
userland, base GCC 12.5, CMake 4.3.3 and Ninja 1.13.2. The front-facing tag
produced a depth of 0.60000 m; the transformed tag produced
`(0.02783, -0.02221, 0.66651)` m, within the declared tolerances. Both consumers
resolved the private installed library. Build guards passed on this VM and
Darwin arm64. The unmodified detection/pose contract also passed on Darwin
with AppleClang 21.0.0. Kernel identity refers to the separately supplied QEMU
boot image, not the guest's `/netbsd` file.
Synthetic images establish library behavior. Camera capture, calibration,
lighting, distortion, occlusion, physical pose accuracy and sustained frame
rate require separate device evidence.

[Provenance and licensing](PROVENANCE.md) records source pins and patch status.
