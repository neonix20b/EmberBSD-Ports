# EmberBSD Ports

Source build recipes, portability patches and build probes for
[EmberBSD](https://github.com/apovalixin/EmberBSD).

Sources are downloaded from their original upstream locations and verified
against pinned hashes. This repository carries our recipes and patches,
with their provenance and validation limits. It does not mirror source
archives or store generated binaries.

## Purpose

Ports supplies the native dependencies used by EmberBSD applications and
examples. It owns the delta over pkgsrc: package recipes, portability patches,
source provenance, shared dependency profiles and reproducible build probes.
Kernel changes belong in EmberBSD; application demonstrations belong in
Examples. A source probe remains experimental until packaging and the intended
runtime behavior are validated.

## Current contents

- [Robotics and ROS 2](profiles/robotics/README.md): Zenoh-Pico 1.10.1
  native package and tests verified; the Examples C controller exchanges
  typed commands and telemetry with ROS 2 Jazzy, including reconnect checks.
- [Common development toolchain](profiles/development-toolchain/README.md):
  GCC 16.2.0 builds and installs as an AArch64 VM candidate, passing native
  C11/C++20 threads, TLS and shared-library runtime checks. The full upstream
  suite exposes platform compatibility failures; a tested upstream backport
  repairs TSVC allocation on NetBSD. Remaining repairs, the common
  Qt/LLVM rebuild and image/default integration remain pending.
- [Current common build tools](profiles/common-build-tools/README.md):
  coherent Python 3.14.8, Meson 1.12.1 and LLVM/Clang/LLD 23.1.2 source
  recipes with upstream lit, scoped native Clang/GCC16 defaults, strict
  common selection and host source contracts. Focused native macro/selection
  checks cover Python, LLVM family selection and real GCC16 config metadata;
  native LLVM23/compiler-family checks, packages,
  installed extensions, ELF consumers and LLVM23/Mesa26 acceptance remain pending.
- [Common graphics source packages](profiles/common-graphics/README.md):
  canonical MesaLib 26.2.4 and adapted libdrm 2.4.134nb1 compose the common
  GCC16/Python314/Meson112/shared LLVM23 profile for NetBSD 11/AArch64.
  Source, export and dependency-selection checks cover X11/Wayland,
  EGL/GBM and classic VirGL/softpipe/llvmpipe. Native package contents,
  consumer migration and renderer runtime remain unverified.
- [Current robotics libraries](probes/robotics-foundations/README.md): native
  OpenCV 5.0.0, Eigen 5.0.1 and gpsd 3.27.5 source probes; installed vision,
  numerical and synthetic GNSS workflows verified on AArch64.
- [Signal processing and IMU estimation](probes/dsp/README.md): liquid-dsp 1.8.3,
  FFTW 3.3.11, VOLK 3.3.0 and Fusion 1.3.3 pass 19 installed AArch64 VM cases.
  They cover filtering, resampling, QPSK, spectra, generic/NEON vector kernels
  and synthetic orientation/bias estimation. Ports preserves the common FFTW,
  source adaptations and pkgsrc patch origins; physical SDR and IMU are unverified.
- [Robotics and automotive developer tools](probes/robotics-tools/README.md):
  MCAP C++ 2.1.3, AprilTag 3.4.5, dbcppp 3.2.6, iso14229 0.11.0,
  Ceres 2.2.0, BehaviorTree.CPP 4.9.0 and libmodbus 3.2.0 source profiles.
  They provide recording/replay, marker pose, DBC decoding, UDS over ISO-TP,
  nonlinear fitting, asynchronous behavior trees and Modbus TCP/RTU.
  All seven pass 19 installed application cases in an AArch64 VM, including
  error paths. Physical camera, CAN/RS-485, ECU and PLC workflows are unverified.
- [Media and OpenCV videoio](probes/media/README.md): FFmpeg 9.0.2,
  GStreamer 1.28.7 and OpenCV 5.0.0 pass installed file/video pipeline checks
  on AArch64, including both videoio backends, timestamps, seeking, lossless
  output and malformed input. Camera capture and acceleration are unverified.
- [MQTT smart-home foundation](probes/mosquitto/README.md): Mosquitto 2.1.2
  builds with common GCC 16.2, cJSON 1.7.19 and SQLite 3.53.4. Twelve installed
  AArch64 VM cases pass MQTT 3.1.1/5 QoS 0/1/2, authentication/ACL, verified
  TLS and retained-state recovery. Packaging, boot service and other
  smart-home ports remain pending.
- [Local AI CPU packages](profiles/ai-cpu/README.md): pkgsrc recipes for
  llama.cpp 0.6.0 and whisper.cpp 1.9.4; native ARM64 package installation,
  text generation, WAV transcription, and loopback HTTP inference verified.
- [CPU inference and audio](probes/ai-engines/README.md): ONNX Runtime 1.30.0,
  ncnn 20260526, RNNoise 0.2 and Silero VAD 6.2.3 pass seven native installed
  consumer checks on AArch64. They cover numerical inference, stream state,
  speech/silence and invalid inputs; explicit ORT worker affinity is checked
  separately. These are source probes, without microphone or accelerator validation.
- [Compass NPU UMD source contracts](probes/compass-umd/README.md): pinned
  upstream descriptor-zero and failure-cleanup fixes pass host/native software
  contracts; public core-count bounds pass 58 native production-extracted cases
  on AArch64/GCC 16.2, with legacy behavior preserved. Kernel/DMA integration
  and model execution remain unverified.
- [SQLite and local document retrieval](probes/sqlite/README.md): SQLite 3.53.4
  installed C consumers pass FTS5/JSON, transactions, concurrent readers and
  process-crash/reopen checks. A C application retrieves local documents and
  validates quotations from the existing llama.cpp CPU server on AArch64.
- [Native Wayland and VirGL build probe](probes/wayland-utm/README.md): pinned
  current Mesa 26.2.4 source adaptation with DSO-lifetime and numeric
  regressions, paired libdrm, wlroots and labwc recipes. Earlier Mesa 21
  software EGL/native KMS-input checks pass; the common Mesa 26 build and
  VirGL hardware runtime remain pending.
- [UTM VirGL host source adaptations](probes/utm-virgl-host/README.md): the
  accepted upstream size-truncation fix is prepared for UTM's pinned 1.3.0
  renderer. Actual-source macOS/arm64 checks show compiled BASE RED and
  patched GREEN across 23 cases, including ASan/UBSan. Local CREATE patches
  also prevent publication after reported renderer failures and unwind owned
  partial allocations; actual-function macOS/arm64 and sanitizer checks pass.
  These are experimental source contracts. Complete host builds, installation,
  async completion/reset, remaining bounds and VirGL runtime remain unverified.
- [Native Phosh session](probes/phosh/README.md): Phosh 0.58.0 builds and
  runs inside GNOME/X11 through Phoc and software-rendered Wayland.
  Stevia screen-keyboard input in English/Russian, a saved text document
  and the patched GTK4 Demo were verified.
- [Current Plasma Mobile](probes/plasma-mobile/README.md): Plasma Mobile
  6.7.5 builds and installs on the AArch64 VM; KWin displays a real Qt Wayland
  window with keyboard input. Activities activation and the upstream
  application menu are checked. The complete mobile workflow still needs
  the common OpenGL stack and an enabled KWin shortcut backend.
  [Qt 6.12/KF6.30 source recipes](probes/plasma-mobile/toolkit/README.md)
  pass source/export checks; their native package migration remains pending.

- [Openbox](probes/openbox/README.md) and
  [Enlightenment](probes/enlightenment/README.md): Openbox 3.6.1 and
  Enlightenment 0.27.1/EFL 1.28.1 pass native software X11 window management,
  keyboard input through XTEST, text editing/saving and session exit.
  The [shared launcher and runtime test](probes/x11-desktops/README.md)
  retain the user's HOME and isolate session configuration and processes.
- [awesomeWM](probes/awesome/README.md): the 4.3 source probe uses LGI 0.9.2
  with the common system Lua. Native build, LGI/icon regressions and the
  same X11 window/input/save/exit workflow pass. Patches correct startup
  pthread linkage, Lua 5.4 version reporting and the WM selection name.
- [Xfce](probes/xfce/README.md): pinned 4.20 components, libwnck 43.3 and
  Mousepad 0.7.0 build and run in an isolated NetBSD 11/AArch64 UTM session.
  [Native checks](probes/xfce/VALIDATION.md) cover Thunar navigation,
  Mousepad save/reopen/edit, menu application launch, X11 window/input
  behavior and clean exit. Hardware input and GPU acceleration are unverified.

The graphical entries remain experimental probes,
not installable packages or phone images. Each recipe records its tested
runtime and platform boundaries.
Helpers stop on errors and keep output in private user directories.

## Package integration

The preferred foundation for package recipes is
[pkgsrc](https://www.netbsd.org/docs/pkgsrc/components.html), already used
by EmberBSD's NetBSD-derived package environment. It provides upstream
fetching, checksums, patches, dependency handling and binary packaging.
This repository does not implement another package manager.

`upstream/pkgsrc` pins the pkgsrc-2026Q3 base as a Git submodule. Local recipes
under `pkgsrc/` use ordinary `Makefile`, `distinfo`, `DESCR`, and `PLIST` files.
`scripts/prepare-pkgsrc.sh` exports that pinned base and adds the local recipes
to an independent working tree. Experimental probes remain under `probes/`
until their package integration and runtime are validated. No signed binary
package repository is provided yet.

## Contributions and provenance

All repository material is written in English. Record the upstream
version, URL, archive hashes, license and origin of each patch. Preserve
upstream copyright and SPDX notices. State whether patches are local,
submitted upstream or accepted upstream; AI assistance is not concealed.

Distinguish a configured project, a compiled library, passing tests and
a working application. Keep logs and downloaded artifacts outside Git.
Examples that use these ports belong in
[EmberBSD Examples](https://github.com/neonix20b/EmberBSD-Examples).

## Related EmberBSD projects

[EmberBSD](https://github.com/apovalixin/EmberBSD#emberbsd-ecosystem) is the
central project and the entry point for the ecosystem.

- [EmberBSD](https://github.com/apovalixin/EmberBSD) — OS, drivers, boards and system builds.
- [EmberBSD-Examples](https://github.com/neonix20b/EmberBSD-Examples) — standalone demonstrations using these dependencies.
- [EmberBSD-Runtime](https://github.com/neonix20b/EmberBSD-Runtime) — application execution and device operations; design stage.
- [EmberBSD-SDK](https://github.com/neonix20b/EmberBSD-SDK) — application contracts and development tools; design stage.
- [Ember-Agent-Skills](https://github.com/neonix20b/Ember-Agent-Skills) — instructions for AI coding assistants, ports and tested contributions.

## Connect developer skills

Use a Codex CLI with plugin support:

```sh
codex plugin marketplace add neonix20b/Ember-Agent-Skills --ref main
codex plugin add emberbsd-development@ember-agent-skills
```

Start a new conversation and ask `$emberbsd-repository-guide` to prepare a
port, run the appropriate checks and open a tested contribution. Follow the
[installation, verification and update guide](https://github.com/neonix20b/Ember-Agent-Skills#install-in-codex)
for the complete procedure and other assistant environments.
