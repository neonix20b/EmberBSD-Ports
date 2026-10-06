# OpenCV, Eigen and gpsd native probe

Validate current stable robotics dependencies on EmberBSD/NetBSD AArch64:
**OpenCV 5.0.0, Eigen 5.0.1 and gpsd 3.27.5**. Upstream release metadata was
checked on 2026-10-06. The pinned pkgsrc base has older OpenCV and Eigen;
this probe deliberately verifies the selected upstream versions.

This is an experimental source probe with a private install prefix. It is
not a pkgsrc binary package, SDK ABI promise or signed distribution channel.

## Sources and dependencies

[sources.tsv](sources.tsv) records the original upstream archives and SHA256.
The source labels remain unchanged. OpenCV uses Apache-2.0; Eigen uses MPL-2.0
with additional notices listed in `COPYING.README`; gpsd uses BSD-2-Clause.
The build preserves their license files. Our probe and tests are MIT-licensed
and AI-assisted. [PROVENANCE.md](PROVENANCE.md) describes the local OpenCV
NetBSD AArch64 CPU-detection patch and its regression test.

Requirements: native C/C++ compiler, CMake, Ninja, curl, pkg-config, SCons 4
and its Python interpreter. The tested build-tool package is `py313-scons`,
whose executable is `scons-3.13`; override with `SCONS` if appropriate.
No project-owned Python is used. Python is required by upstream gpsd/SCons
at build time; the selected runtime excludes Python bindings, GUI clients and
shared-memory position export.

OpenCV includes `core`, `imgproc`, `imgcodecs`, `features`, `geometry`, `calib`
and their required dependencies. It uses Eigen 5.0.1 and the native CPU path.
The profile excludes GUI, video backends, GPU/OpenCL/Vulkan, DNN and optional
external image codecs. PPM encoding/decoding is tested. This does not establish
PNG/JPEG, camera acquisition, all OpenCV modules or accelerated inference.

## Build and test

Use a fresh absolute work directory without whitespace, outside this checkout.
The script refuses an existing directory. Root is not required when building
into a writable private directory. Run the daemon tests in a disposable lab
VM with active loopback and ptyfs mounted on `/dev/pts`. A normal multi-user
boot provides this; a single-user guest needs its ordinary ptyfs preparation.
Upstream gpsd attaches NTP shared-memory segments at startup, even for a PTY;
it does not publish simulated PTY time into those segments.

```sh
export PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/usr/sbin:/bin:/sbin
work=/var/tmp/ember-robotics-foundations
sh probes/robotics-foundations/build.sh "$work"
sh probes/robotics-foundations/test.sh "$work"
```

The optional second argument to `build.sh` is a directory containing all three
pinned archives. Every hash is checked before any archive is extracted.
`JOBS=1` is the default for limited-memory guests. Full stage logs remain in
`WORK/logs`; installation is `WORK/install`. A failing stage preserves its
exit status and prints its log tail. Reuse of an existing build directory is
not presented as a clean rebuild.

`test.sh` compiles consumers against the installed CMake/pkg-config metadata,
requires exact versions, runs CTest and records dynamic linkage. It checks:

- Eigen dense/sparse solve residuals, SVD reconstruction, rank-deficient
  input, rotation/translation and the inverse transform, tolerance 1e-12.
- OpenCV lossless PPM round trip, exact segmentation area/centroid, edges,
  ORB extraction and self-matching, camera pose recovery (1e-6), Eigen
  conversions, malformed and empty image rejection.
- A real gpsd child receiving synthetic NMEA on a newly allocated PTY, read
  through installed libgps: 3D fix/altitude, invalid-checksum rejection,
  explicit loss of fix and a new recovered position.
- A missing daemon or missing input must fail within the deadline. The harness stops only its
  own child and closes its PTY; no persistent daemon or device is configured.
- Build guards reject an existing work tree, a corrupt archive before extraction
  and zero build parallelism.

The build also runs upstream gpsd `scons check` for this configuration. With
Python bindings disabled, upstream's Python daemon-replay tests are omitted;
our C PTY test supplies the explicit installed-daemon scenario. NMEA2000/CAN
regression needs a separate CAN environment and is not established here.

## Validation boundary

Verified on 2026-10-06 in QEMU 11.1.2/HVF AArch64: one vCPU, 2 GiB RAM,
NetBSD 11.0 userland and the EmberBSD EMBER64 kernel from
`b4f718dabd085ed117a24f84d8558e4a43091dc0`. GCC 12.5.0, CMake 4.3.3,
Ninja 1.13.2, SCons 4.10.1 and upstream Python 3.13.14.

All three source builds and private installations completed. The final
installed suite passed **6/6 tests in 24.33 seconds**, including both expected
failure cases and the build guards. gpsd's configured upstream `check` also
passed; it warns about the missing `__STDC_IEC_559__` macro while the floating
point tests pass. Python replay, NMEA2000 and optional tool-dependent checks
are excluded as described above. The full upstream Eigen/OpenCV suites were
not run; the selected installed workflows are the runtime evidence.

The initial unpatched OpenCV library aborted at startup. The local CPU-baseline
patch fixed that regression without disabling NEON or the baseline guard.
Optional ARM extensions remain unadvertised. OpenCV resolved Eigen 5.0.1 and
system zlib 1.3.1; `ldd` resolved the installed OpenCV/gpsd libraries and base
system libraries with no missing dependency. Required module dependencies also
built `flann`, `objdetect` and `stereo`; their complete APIs are not covered.

Synthetic images and NMEA establish software behavior only. Physical cameras/GNSS receivers,
USB/Bluetooth transport, PPS timing, real-time deadlines, SMP stability and
other boards require separate evidence. The probe never configures hardware.

The general design and validation plan are in
[docs/robotics-foundations](../../docs/robotics-foundations/design.md).
