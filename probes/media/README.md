# Native media developer profile

Build **FFmpeg 9.0.2** and **GStreamer 1.28.7** as installed development
libraries on EmberBSD. The C consumers encode and validate deterministic
video, exchange timestamped application buffers, read a raw video file and
handle end-of-stream and invalid input. An optional second stage enables
**OpenCV 5.0.0 videoio** against the same media installation.

This experimental source probe belongs to Ports. It is not yet a pkgsrc
package or a replacement for the media packages used by an active desktop.
Use a disposable native VM and a fresh private work directory. One current
version of each dependency is selected; the temporary prefix is removed after
validation or replaced by coordinated package integration.

## Dependencies and scope

Use the native C/C++ compiler with C11/C++17, GNU make, CMake, Ninja, Meson,
Bison, flex, pkg-config, GLib development files, glib-mkenums, curl, tar, patch
and sha256/readelf. In a normal NetBSD-derived package environment, the additional
packages are `gmake cmake ninja-build meson bison pkgconf glib2 glib2-tools python313 curl patch`.
Install both GLib packages: `glib2-tools` does not provide the library/SDK.
Meson and upstream
GLib/GStreamer generators require Python at build time. Our scripts and tests
use shell, C and C++; no Python runtime is needed by these consumers.
The default interpreter is `python3.13`; set `PYTHON` to another supported
installed interpreter if required. A work-directory `python3` symlink names
that same interpreter for upstream shebangs; it does not install another Python.

FFmpeg enables FFV1, raw video and signed 16-bit PCM, with Matroska, AVI, WAV
and raw-video containers and local file/pipe protocols. Its scaler and
resampler remain available. Network protocols, hardware devices, optional
external codecs, GPL and nonfree components are disabled. CLI tools are built;
this profile is deliberately not a general-purpose distribution of all codecs.

GStreamer builds core and plugins-base with appsrc/appsink, raw parsing,
video conversion/scaling, video/audio test sources, audio conversion and
resampling. It uses the existing GLib, disables optional external codecs,
OpenGL, GUI and hardware integration, and prohibits automatic dependency
source downloads. The test environment limits plugin loading to this prefix.
The recipe also pins GLib's pkg-config libintl link to its existing base ABI
when needed; this avoids loading both base and pkgsrc libintl in one process.
The local metadata overlay and removal condition are documented in provenance.

[Source hashes](sources.tsv), [provenance and patch status](PROVENANCE.md),
and [probe license](LICENSE) accompany the profile. Upstream license files
are installed alongside it. OpenCV's FFmpeg compatibility patch retains its
upstream authors and Apache-2.0 license; the surrounding probe is AI-assisted
EmberBSD work under MIT.

## Build and verify the media libraries

Use a new absolute path containing only letters, digits, slash, dot, underscore
or hyphen. The scripts refuse an existing media work directory and preserve
failed-stage exit status. Source hashes are checked before any extraction.
Build output and fixtures stay outside the repository. `JOBS=1` is the default.

```sh
export PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/usr/sbin:/bin:/sbin
work=/var/tmp/ember-media
sh probes/media/build.sh "$work"
sh probes/media/test.sh "$work"
```

An optional second argument to `build.sh` supplies a directory containing the
three archives named in `sources.tsv`. Installation is `WORK/install` and
build logs, tool versions and source receipts are in `WORK/logs`.
The original archive names and upstream directory names are unchanged.

`test.sh` builds installed C consumers through pkg-config and requires exact
header/runtime versions. It runs these contracts under bounded deadlines:

- FFmpeg: encode twelve 64×48 grayscale frames at 25 fps to FFV1/Matroska;
  read the file and compare every pixel, PTS and frame count; drain both
  encoder and decoder and require container EOF.
- FFmpeg failures: missing, same-size malformed, midstream-truncated and
  tail-truncated files (one and 64 bytes removed) must fail without a PASS.
  The strict known-fixture reader requires the trusted original byte length
  and rejects decoder/container warnings. Matroska can produce all frames
  after trailer damage; frame count alone cannot establish file completeness.
  This contract validates our generated fixture, not arbitrary Matroska files.
- GStreamer: push timestamped GRAY8 buffers through appsrc, videoconvert and
  appsink; compare every BGR channel, PTS and duration; require both appsink
  and bus EOS. Incompatible caps must produce a negotiation error.
- GStreamer file input: write and read a raw grayscale fixture through
  filesrc/rawvideoparse/appsink; require exact pixels, frame count, PTS and EOS.
- Build guards: reject zero parallelism, an existing work directory and a
  corrupt archive before extraction.

`WORK/logs/installed-linkage.txt` records dynamic linkage and must resolve
FFmpeg and GStreamer libraries from the selected prefix. Plugin versions and
paths are also checked and printed. The tests never configure devices,
network listeners, startup services or login sessions.

## Add OpenCV videoio after media acceptance

```sh
EIGEN_PREFIX=/absolute/common-foundations/install sh probes/media/build-videoio.sh "$work"
VIDEOIO=ON sh probes/media/test.sh "$work"
```

The optional second argument is a cached `opencv-5.0.0.tar.gz`. Its SHA256 is
checked against the existing robotics profile. The build reuses the local
NetBSD AArch64 CPU-baseline patch from
[robotics-foundations](../robotics-foundations/PROVENANCE.md) and the accepted
upstream FFmpeg 9 compatibility series. A second local patch enables the
existing POSIX filesystem implementation on NetBSD; GStreamer capture calls it.
It builds the union of media and robotics OpenCV modules into the same prefix,
using common Eigen 5.0.1 and existing system PNG/JPEG development libraries.
No second FFmpeg or GStreamer is installed.
The V4L camera backend is explicitly disabled. OpenCV 5.0.0 auto-detects
NetBSD's `sys/videoio.h` but its V4L source then fails on Linux-only integer
types. This file-processing profile does not supply a camera portability fix.

The C++ contract requests `CAP_FFMPEG` and `CAP_GSTREAMER` explicitly, checks
the selected backend, and verifies FFmpeg file capture, timestamps, seeking,
threshold processing, lossless FFV1 write/read and malformed/missing input.
GStreamer reads a deterministic raw video file through a manual pipeline.
Every decoded pixel and the final frame count are checked. GStreamer's OpenCV
position query is not treated as a per-buffer timestamp; the C contract
checks those PTS values directly. Linkage is retained in `videoio-linkage.txt`.
The filesystem regression also checks existing/missing paths, directory
creation, recursive globbing, canonical paths and removal of its own test tree.

## Validation boundary

Verified on 2026-10-07 in a disposable QEMU/HVF AArch64 VM with one vCPU,
3 GiB RAM, NetBSD 11.0 userland and the EmberBSD EMBER64 kernel from
`b4f718dabd085ed117a24f84d8558e4a43091dc0`. Native GCC 12.5.0, CMake 4.3.3,
Meson 1.11.1, Ninja 1.13.2, GNU make 4.4.1, Python 3.13.14 and GLib 2.88.1.

The original smaller media configuration was validated as follows; these
results do not validate the prepared shared robotics configuration below.
The three media source builds and OpenCV installation completed. The final
installed suite passed **5/5 tests in 0.58 seconds**, including the explicit
filesystem regression, both OpenCV backends and tail-truncation regressions.
The private installation occupies 35 MiB; build/source/test work occupies
606 MiB in this configuration. These figures exclude the system toolchain.
Linkage resolves FFmpeg, GStreamer and OpenCV from the same prefix and only
the base libintl ABI. Installation and test fixtures stay in the selected
work directory.

Two OpenCV failures have distinct treatment: the required filesystem path is
fixed and tested; the unrelated V4L camera backend is explicitly excluded.
The accepted FFmpeg 9 compatibility backport permits the current media stack.

These deterministic CPU workflows do not establish physical camera capture,
audio hardware, compressed audio, arbitrary codec coverage, network streaming,
GPU/NPU acceleration, sustained throughput or support on a particular board.
The full upstream FFmpeg, GStreamer and OpenCV suites are not run by this probe.
System package migration must account for every existing consumer before
replacing a desktop's shared library stack.

## Prepared shared OpenCV configuration

The current `build-videoio.sh` source recipe expands that same provider to
`core,imgproc,imgcodecs,features,geometry,stereo,calib,video,stitching,photo,videoio`
and required dependencies. It requires `EIGEN_PREFIX` pointing to common
Eigen 5.0.1 and existing PNG/JPEG development libraries, with bundled codec
builds disabled. It uses `JOBS=1` and imposes no address-space limit by default.
An explicit positive `BUILD_AS_KIB` requests a verified soft limit; the
inherited hard limit is preserved.

The explicit stereo export preserves the OpenCV 5 module required by the
adapted ORB-SLAM3 consumer.

```sh
EIGEN_PREFIX=/var/tmp/ember-robotics-foundations/install \
sh probes/media/build-videoio.sh "$work"
VIDEOIO=ON sh probes/media/test.sh "$work"
```

An additional image-codecs contract checks exact 16-bit PNG depth, bounded RGB
JPEG error and malformed input rejection. The expanded configuration is **not
natively validated yet**. The earlier 5/5 result and footprint describe the
smaller original profile. Rebuild the current FFmpeg/GStreamer recipes if their
private installation was removed, then revalidate media, foundations and ORB
against this provider. No second OpenCV installation is part of the target stack.
