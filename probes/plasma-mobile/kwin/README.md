# Current KWin native NetBSD build probe

## Original sources

All source archives are fetched from KDE and checked against the corresponding
KDE-published `.sha256` file on 2026-10-06. The SHA256 values below are pinned.

| Archive | SHA256 |
| --- | --- |
| kwin-6.7.5.tar.xz | `6baa910b732d93c48c90f9c1cc685cc93d0b8de0cdf138c24192c045bc3a48e2` |
| knighttime-6.7.5.tar.xz | `5cb23e736e4be4952e63c855cfb45850e1085d650e67b7cae3cbf9721921cb9f` |
| kdecoration-6.7.5.tar.xz | `7ff1fe2854ca08a21a1ba47f1b0c97d12ea24f1db618631319cba4023ca53d86` |
| kwayland-6.7.5.tar.xz | `8d4c83524919dc87b5dec546d0fb14c591c03957888cb7b240a4a9d1bbdc8269` |
| plasma-wayland-protocols-1.23.0.tar.xz | `16c5ad917bde2ed795942dacba76654819ddc6a1566842325ef34e0b553ef138` |

Plasma source base URL: https://download.kde.org/stable/plasma/6.7.5/

Protocols source base URL: https://download.kde.org/stable/plasma-wayland-protocols/
The directory dates protocols 1.23.0 to 2026-09-24.

Preserve every upstream copyright/SPDX header and `LICENSES/` directory.
The main compositor uses GPL-2.0-or-later; individual files carry additional
GPL, LGPL, BSD, MIT and CC0 licensing. The original SPDX headers are authoritative.

## Patch origins

The pkgsrc-wip recipe was inspected at commit
`60460008d0c770590e46fc229035b8e454472a80`:
https://github.com/NetBSD/pkgsrc-wip/tree/60460008d0c770590e46fc229035b8e454472a80/plasma6-kwin

1. `01-bsd-executable-path-source.patch` is unchanged from pkgsrc-wip
   `patch-src_utils_CMakeLists.txt`; its original `$NetBSD$` header is retained.
2. `02-netbsd-executable-path.patch` is a local, AI-assisted EmberBSD change,
   not submitted upstream. NetBSD queries `CTL_KERN, KERN_PROC_ARGS, pid,
   KERN_PROC_PATHNAME`. The FreeBSD tuple returns a zero-byte response on the
   tested NetBSD 11 system. The patch rejects empty responses and avoids an
   allocated `realpath()` buffer leak.
3. `03-system-cxx-ranges.patch` is a local, AI-assisted EmberBSD change,
   not submitted upstream. It materializes the sequence containers used by
   KWin with C++20 range iteration and expresses membership through `find`.
   This permits native GCC 12.5 with the same system `libstdc++.so.9` as Qt.
   The available GCC 15 package instead links `libstdc++.so.7`; strict linking
   correctly rejects loading both runtime versions. No undefined symbol is
   allowed and no extra C++ runtime is loaded.
4. `04-pair-return-type.patch` is a local, AI-assisted EmberBSD change,
   not submitted upstream. Two returns now construct the declared `std::pair`
   directly rather than relying on a newer tuple-like conversion constructor.
5. `05-unused-format-header.patch` is a local, AI-assisted EmberBSD change,
   not submitted upstream. It removes an unused `<format>` include from the
   keyboard implementation. No formatting operation is changed.
6. `06-netbsd-icccm-headers.patch` is a local, AI-assisted EmberBSD change,
   not submitted upstream. Qt's transitive base X11 include directory can
   precede the current discovered XCB ICCCM headers on NetBSD. The two source
   files using ICCCM explicitly prefer the include directory of `XCB::ICCCM`.
   The discovered modern library and its matching API remain in use.
7. `07-vulkan-dynamic-dispatch.patch` is a local, AI-assisted EmberBSD change,
   not submitted upstream. Three physical-device queries now use the existing
   Vulkan-Hpp RAII instance dispatcher. CMake can therefore use `Vulkan::Headers`
   for the existing dynamic loader. No direct Vulkan symbols or mandatory
   Vulkan DSO dependency remain in libkwin. The installed Vulkan loader itself
   is still defective: it imports libc `alloca`; Vulkan runtime is not certified.
8. `08-netbsd-compatibility-warnings.patch` is a local, AI-assisted EmberBSD
   change, not submitted upstream. NetBSD's base libutil compatibility aliases
   emit nine `.gnu.warning` messages through Qt's transitive dependencies.
   These diagnostics remain visible; their fatal status is removed only on
   NetBSD, with `--no-undefined` retained. Before this change, a strict relink
   after patch 07 confirmed that the separate Vulkan `alloca` warning was gone.
9. `09-discovered-metadata-interpreter.patch` is a local, AI-assisted EmberBSD
   change, not submitted upstream. It calls the unchanged upstream generator
   through CMake's `Python3::Interpreter` target rather than assuming a
   `python3` executable alias exists.
10. `10-netbsd-memfd-page-size.patch` is a local, AI-assisted EmberBSD change,
    not submitted upstream. NetBSD 11 rejects an mmap whose final rounded page
    extends beyond the exact memfd length. Only the backing allocation is
    rounded up; the logical keymap/buffer size and all seals are preserved.
    Native probes reproduce the failure for 4095, 4097 and 1920000 bytes,
    while page-rounded allocations work. All eight grow/shrink/write-seal
    checks pass. Reassess this workaround after the OS fixes partial-page
    memfd mappings.

The earlier pkgsrc-wip QPA compatibility fix is already present in KWin 6.7.5.
Its patch disabling all RAM-file seals is unnecessary: NetBSD 11 provides
`memfd_create`, `F_ADD_SEALS`, `F_GET_SEALS`, and the required seals.
The page-size workaround preserves that protection.
Its unresolved-symbol linker flag is excluded. The validated libopeninput 1.30.2
installation exports all 198 libinput functions called by KWin 6.7.5.

Patches 03--05 support the current base GCC 12 probe. When Qt, KDE Frameworks
and their consumers move together to the new common GCC toolchain, retest the
original C++23 code and remove compatibility patches that are no longer
needed. The NetBSD executable-path and discovered-header fixes have separate
OS/build-system causes and must be assessed independently.

## Build profile and limits

The build uses installed Qt 6.11.1, KDE Frameworks 6.26.0 and system GCC 12.5.
All Plasma support libraries are 6.7.5, with protocols 1.23.0. The shared current
Plasma prefix is supplied by the caller. The input library comes from the
caller-selected validated libopeninput installation. DRM, GBM and EGL use the
existing X11R7 installation. The probe shares one current Plasma prefix rather than building copies per
application. Older packaged Plasma libraries may remain during migration and
must not satisfy the current probe.

The initial validated profile disabled global shortcuts. The current recipe
requires matching `KGlobalAccelD` and enables them: Mobile invokes its task
switcher through KWin's `org.kde.kglobalaccel` interface. Build that dependency
in the shared prefix using [the common recipe](../BUILDING.md).
Configuration modules, screen locking, runners and decorations remain disabled.
DRM, libinput, nested X11/Wayland and
virtual backends remain compiled. The intended runtime explicitly selects
nested X11 with software rendering and an empty `KWIN_RENDER_NODES` list.

The upstream KWin build runs `strip-effect-metadata.py` through Python 3.
This probe adds no Python helper and does not claim a Python-free build.

`scripts/ranges-probe.cpp` tests filtered/transformed materialization, an empty
range, derived-to-base pointers, QStringList and a unique_ptr projection.
It passes with system GCC 12.5 and strict linker flags, loading only the system
C++ runtime. `scripts/sysctl-path-probe.c` demonstrates the NetBSD MIB behavior.

Configuration, compilation, strict linking, nested runtime, hardware runtime,
and a working Plasma Mobile shell are distinct validation levels. No hardware
backend support follows from a nested test.

## Reproduction

Download the five pinned archives above into an external archive cache, or
use the shared [source preparation helper](../BUILDING.md#common-sources-and-prefix).
Build as the unprivileged owner of the build directory. Set `PLASMA_PREFIX` to the shared
6.7.5 installation and `LIBINPUT_PREFIX` to the validated input installation:

```sh
export PLASMA_PREFIX=/path/to/shared/plasma/install
export LIBINPUT_PREFIX=/path/to/validated/libopeninput/install
export BUILD_ROOT="$HOME/.cache/emberbsd-plasma-kwin"
export ARCHIVE_DIR=/path/to/verified/archive/cache
JOBS=1 sh scripts/build-kwin-dependencies.sh
JOBS=1 sh scripts/build-kwin-6.7.5.sh
KWIN_SOURCE_DIR="$BUILD_ROOT/src/kwin-6.7.5" sh scripts/check-portability.sh
CONTRACT_DISPLAY=:79 sh scripts/check-nested.sh
```

`ARCHIVE_DIR` defaults to `$BUILD_ROOT/archives`. `SOURCE_ARCHIVE` can override
the KWin archive path alone. Both helpers verify source hashes before use.
`CONFIGURE_ONLY=1` stops the KWin helper after generating build files.
Both builders default to base `cc`/`c++` and honor explicit `CC`/`CXX` paths.
Override them only when Qt, KDE and all C++ consumers move to the same runtime;
changing KWin's compiler alone is not a compatible toolchain migration.

Choose an unused X display for the final command. The runtime check requires
Xvfb, XTest development files, xwd, xwininfo, xdpyinfo, dbus-daemon and Qt's
qdbus client.
It records its evidence in a new `$BUILD_ROOT/contract/run.*` directory.
All four private XDG directories exist before the bus starts; `HOME` remains
unchanged. The private bus has no included configuration or service directories,
so it cannot activate desktop helpers. See the
[dbus-daemon configuration reference](https://dbus.freedesktop.org/doc/dbus-daemon.1.html).

Cleanup signals only recorded child PIDs, waits at most five seconds after
TERM and two after KILL, and calls `wait` only after the child is absent.
It checks the private sockets and the X11 socket/lock. An X11 node is removed
only when its lock still names the exited owned X server. Foreign nodes are
preserved. Cleanup failure changes an otherwise successful exit to failure;
the final PASS is printed only after cleanup succeeds.

Run `sh scripts/check-nested-lifecycle.sh` for the small lifecycle regression.
It needs a C compiler, dbus-daemon and dbus-send, but no KWin or X server.
It checks private XDG state, unchanged HOME, a synthetic service that must not
activate, TERM/KILL handling, failed-KILL bounds, foreign lock preservation,
cancellation status and suppression of PASS after a cleanup failure.

The KWin source stamp contains a SHA256 fingerprint of the pinned archive hash
and each ordered patch hash/name. An existing source tree with a missing or
different stamp is rejected, never overwritten. Use a fresh `BUILD_ROOT` when
the patch set changes. `PREPARE_ONLY=1` performs source preparation without
configuring or compiling. Native checks passed for a fresh tree, an identical
repeat, rejection of a changed patch, and rejection of the old empty stamp.
The stamp records preparation inputs; it does not detect later manual source
edits. Keep changes in the patch series and prepare a fresh tree for release.

The small C diagnostics can be compiled directly on NetBSD:

```sh
cc scripts/memfd-mmap-probe.c -o "$BUILD_ROOT/memfd-mmap-probe"
cc scripts/memfd-seals-probe.c -o "$BUILD_ROOT/memfd-seals-probe"
"$BUILD_ROOT/memfd-mmap-probe"
"$BUILD_ROOT/memfd-seals-probe"
```

The mmap diagnostic reports every case and returns success after completing
the matrix, even when a mapping reproduces the known OS failure. The seals
check returns nonzero on a failed contract.

## Native result, 2026-10-06

KWin 6.7.5 built and installed on NetBSD 11.0 aarch64, kernel `EMBER64 #0`,
with GCC 12.5.0. Runtime inspection found only system `libstdc++.so.9` and the
selected libopeninput. The nested test reported `Compositing Type: QPainter`.
A real Qt Wayland client rendered its window and received `emberbsd` through
XTest, the nested compositor and Wayland keyboard delivery. The exact receipt
was `platform=wayland` followed by `text=emberbsd`. The captured frame was
visually checked. All owned processes were reaped, and their X11/Wayland
sockets were verified absent afterwards.

The revised lifecycle runner also passed natively: two consecutive real
Wayland drawing/input runs reused the same X display, cancellation returned
143 without PASS, and an explicitly killed owned Xvfb left no socket or lock
after cleanup. The native lifecycle regression additionally exercised a child
that ignores TERM, escalation to KILL, simulated failure to exit after KILL,
and preservation of a foreign X11 lock. Its synthetic D-Bus service was not
activated. These checks did not rebuild KWin.

Installed artifact SHA256 values for that run:

| Artifact | SHA256 |
| --- | --- |
| `bin/kwin_wayland` | `987967e0bdaf64d9144f2e9cb5c71582cd9c9e4ea5b852bc41b640256686b2eb` |
| `lib/libkwin.so.6.7.5` | `51db7e92b6d347ef185d7734495b0ed4bcbd60c4384a542ba0936098360c83dc` |

The source-preparation fingerprint was
`5e396b3f50046f0b395cfbbcb0ad6160a9bacc822a8c33731c8ff036c5f777e5`.
These hashes identify this build; installation paths can affect a rebuild's
binary identity.

This is a basic window/input checkpoint. OpenGL, Vulkan, native DRM/KMS,
mobile task switching and long-running stability remain unverified here.
See [the graphics contract](MOBILE-GRAPHICS-CONTRACT.md) for the required next
check on the common Mesa/toolchain stack. This recipe's default base compiler
and temporary C++23 adaptations must be reassessed during that shared upgrade.
