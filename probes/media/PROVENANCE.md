# Media source provenance

Upstream stable release pages checked on 2026-10-07:

- [FFmpeg 9.0.2](https://ffmpeg.org/download.html), released 2026-09-18.
- [GStreamer 1.28.7](https://gstreamer.freedesktop.org/releases/1.28/), released 2026-09-07.
- [OpenCV 5.0.0](https://github.com/opencv/opencv/releases/tag/5.0.0),
  confirmed as the latest stable release on 2026-10-07.

[sources.tsv](sources.tsv) pins the original release archives and SHA256.
The selected FFmpeg configuration is LGPL-2.1-or-later: GPL and nonfree
components are disabled. GStreamer core and plugins-base are LGPL-2.1-or-later.
Upstream licenses are copied into the private installation. Preserve the
complete upstream notices when redistributing a binary or modified source.

The FFmpeg and GStreamer sources are unmodified. FFmpeg explicitly receives
`--enable-pic`: its NetBSD configuration does not enable PIC by default,
and an unmodified shared AArch64 build otherwise fails to link `libavutil`
with `R_AARCH64_ADR_PREL_PG_HI21` relocations. This uses an upstream configure
option rather than a source patch.

The C contracts and shell/CMake
orchestration are original EmberBSD work, AI-assisted and MIT-licensed.
No copied third-party sample code or generated media is committed.
Upstream Meson and GLib's glib-mkenums require Python at build time.
The consumers have no Python runtime dependency.
GStreamer generators use `/usr/bin/env python3`; a temporary work-directory
symlink resolves this to pkgsrc's selected `python3.13` binary. Sources and
system interpreter paths are unchanged.

The tested pkgsrc GLib 2.88.1 library depends on base `libintl.so.1`, while
its pkg-config metadata exports bare `-lintl` after `/usr/pkg/lib`. That can
silently add pkgsrc `libintl.so.8` to the same process. When ELF dependencies
confirm the base ABI, the recipe creates a private-prefix `glib-2.0.pc`
overlay that pins `/usr/lib/libintl.so.1` instead of bare `-lintl`. Other GLib
metadata stays unchanged; its original checksum is logged. No installed
package or system symlink is changed and no second GLib is built. Tests
reject mixed libintl ABIs. Remove this overlay once the chosen package
metadata resolves the same libintl ABI as its GLib library without it.

Installed pkgsrc multimedia packages are inventory evidence only. Their
FFmpeg 8.1.1 and GStreamer 1.28.3 versions do not define this profile. The
probe builds one current private stack without replacing a running desktop's
libraries. This temporary prefix is a validation artifact, not a second
permanent system package family. Package migration and consumers of older
system ABIs require a coordinated package update before image integration.

## OpenCV videoio

OpenCV 5.0.0 comes from tag `5.0.0`, commit
`40738fb16ceddb5fb3fea747585f7ce6abb0605b`, with Apache-2.0 licensing.
The archive is https://github.com/opencv/opencv/archive/refs/tags/5.0.0.tar.gz;
SHA256 is `b0528f5a1d379d59d4701cb28c36e22214cc51cf64594e5b56f2d3e6c0233095`.
The baseline CPU patch is reused from
[robotics-foundations](../robotics-foundations/PROVENANCE.md), not reapplied
to an already patched tree.

`patches/opencv-ffmpeg9-upstream.patch` is the unmodified three-commit series
from [OpenCV PR 29533](https://github.com/opencv/opencv/pull/29533.patch),
downloaded 2026-10-07. SHA256:
`13bfd0f570e79d3dccd9652439a5413235cf0fffe74a87951f439ba45c039ad6`.
It preserves authors Aadhu23, Arnesh Banerjee and Alexander Smorkalov,
and these upstream commits:

- `700cd32ffd59ed3c6f6aec1919867653d8b125ea`
- `83ed22ca2800267050a4a9a94afab605c990c0e0`
- `c0166c617d765ac707dde6b9acd8cfcd49751049`

The series was accepted into upstream's 4.x branch on 2026-08-11. It replaces
removed `AVCodec::pix_fmts` and `supported_framerates` access with
`avcodec_get_supported_config` for modern FFmpeg. OpenCV 5.0.0 lacks the fix;
we backport the accepted series instead of pinning an older FFmpeg. The
upstream status applies to the original changes, not to our NetBSD build or
our selection of modules. Our application and verification of the series are
AI-assisted. No upstream submission is made by this probe.

The selected OpenCV configuration disables V4L. Automatic detection accepts
NetBSD's `sys/videoio.h`, but upstream `cap_v4l.cpp` uses undefined Linux
`__u32`/`__s32` types there. This probe requests FFmpeg/GStreamer file input,
so the camera backend is excluded explicitly rather than patched without a
physical-camera acceptance test. Camera portability remains unverified.

## OpenCV NetBSD filesystem support

`patches/opencv-netbsd-filesystem.patch` enables NetBSD in the existing POSIX
filesystem feature guard and implementation branches. OpenCV 5.0.0 otherwise
sets `OPENCV_HAVE_FILESYSTEM_SUPPORT=0`; the GStreamer backend calls `exists`
and fails with `StsNotImplemented` before constructing a pipeline. The 5.x
upstream header checked on 2026-10-07 still omits NetBSD.
Patch SHA256: `a574b9b8edf25a3d39e30096fb60a872f33c27dab38688bb45e57451fea75f76`.

The patch preserves the upstream POSIX implementations of stat, realpath,
getcwd, mkdir, fcntl locks and cache-directory discovery. It adds no stubs or
Linux API emulation. The installed C++ regression checks existing/missing
paths, directories, current directory, recursive creation, globbing, canonical
paths and removal of its own fixture tree, then the GStreamer file workflow
that originally failed. Lock contention and cache policy are not independently
tested by this probe. This local, AI-assisted adaptation is Apache-2.0 like
the modified OpenCV files; it has not been submitted or accepted upstream.

## Shared robotics configuration (source preparation)

The same OpenCV 5.0.0 provider now includes the union of media and robotics:
`core,imgproc,imgcodecs,features,geometry,stereo,calib,video,stitching,photo,videoio`
and required upstream module dependencies. `EIGEN_PREFIX` selects the existing
Eigen 5.0.1 installation. PNG and JPEG use existing system development libraries;
`BUILD_PNG=OFF` and `BUILD_JPEG=OFF` prevent new private codec providers.
The archive and all three existing portability patches are unchanged.

ORB-SLAM3 uses the explicit stereo export after the OpenCV 5 module split.
OpenVINS uses video/KLT. RTAB-Map core uses stitching exposure compensation,
photo exposure fusion, video tracking, videoio camera classes, and imgcodecs
PNG depth/JPEG RGB database compression. Qt, highgui, V4L and hardware backends
remain outside this selected profile. The image-codecs consumer checks exact
16-bit PNG depth, bounded JPEG error and malformed input rejection.

This expanded configuration has not yet been built or validated natively.
The earlier 5/5 result and footprint apply only to the original smaller media
configuration. Revalidate media, foundations and ORB consumers before replacing
the old foundations OpenCV files. Preserve its Eigen and gpsd installation.
No address-space limit is imposed by default. An explicit positive
`BUILD_AS_KIB` sets and verifies only a soft limit; the inherited hard limit
is preserved. `JOBS=1` is the default. No VM-wide resource setting is changed.
