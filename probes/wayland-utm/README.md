# Native Wayland and VirGL build probe

This experimental probe builds libdrm, Mesa with the VirGL Gallium driver,
wlroots and labwc in a private prefix on EmberBSD/NetBSD 11 aarch64.
It does not replace the installed X11 libraries or change the login session.
Kernel DRM/KMS and an accelerated host VirtIO-GPU are separate prerequisites.
A successful build does not establish native Wayland or GPU acceleration.

## Sources and patches

[`sources.tsv`](sources.tsv) records the exact upstream archive URLs and
SHA256. Each archive is checked before extraction. The downloaded bytes also
matched the SHA512 in pkgsrc's pinned `distinfo` during initial preparation.

| Component | Version | Upstream license |
|---|---|---|
| libdrm | 2.4.134 | MIT and source-file notices |
| Mesa | 21.3.9 | MIT and source-file notices |
| wlroots | 0.19.3 | MIT |
| labwc | 0.9.7 | GPL-2.0-only |

The imported NetBSD adaptations under `patches/` are copied unchanged from
[pkgsrc 0491f5e57e8fba00998bf1a6c0958ef421fefaa1](https://github.com/NetBSD/pkgsrc/tree/0491f5e57e8fba00998bf1a6c0958ef421fefaa1):
`x11/libdrm`, `graphics/MesaLib`, `wayland/wlroots`, `wayland/labwc` and
`sysutils/seatd`.
Their NetBSD identifiers and provenance notes are retained. These are pkgsrc
patches; this probe does not claim upstream acceptance.

Local AI-assisted adaptations are not submitted upstream:

- libdrm and Mesa symbol tests apply their existing ELF bookkeeping-symbol
  allowlist to NetBSD. Missing public symbols and unknown API exports remain
  errors.
- Mesa's dispatch-index test uses POSIX expressions understood by NetBSD sed.
- Mesa's half-to-float conversion normalizes with integer operations. The
  original floating-point intermediate loses binary16 subnormals when the
  process flushes binary32 subnormals. Its exhaustive 65536-value test exposed
  2046 failures on the target VM before the fix and passes afterward.

Source license and copyright notices remain in the original archives.
The project-owned shell helpers and regression test use the included
BSD-2-Clause license; that license does not relicense upstream patches.

The probe follows these pkgsrc versions to keep a known NetBSD adaptation
base. It enables VirGL explicitly; pkgsrc's MesaLib recipe leaves it disabled.
Mesa uses softpipe as its optional software fallback. LLVM is disabled in this
private build: the installed LLVM 21 is newer than this Mesa release's supported
LLVM interfaces. The installed GNOME llvmpipe stack remains separate.

## Build

Use an ordinary user, an absolute new build directory and a compiler/toolchain
appropriate for NetBSD 11. The helper never elevates its own privileges.
Install dependencies through the normal package environment first:

```sh
pkgin install meson ninja-build bison flex py313-mako \
    seatd libopeninput libdisplay-info libsfdo \
    hwdata xcb-util-errors
```

The existing desktop environment supplies Wayland, Wayland protocols,
libxkbcommon, pixman, libudev-bsd, expat, zlib, zstd, libepoll-shim, glib2,
cairo, pango, librsvg, libxml2, XCB and related development metadata.
Meson reports any missing or insufficient dependency and the helper stops.
This is not yet a complete pkgsrc package or dependency resolver.

Meson, upstream Mesa generators and libdrm tests require Python 3.13 and Mako.
The project helper itself is shell. Set `PYTHON` only to another compatible
absolute interpreter path; `JOBS` defaults to three.

```sh
sh build.sh "$HOME/.cache/emberbsd-wayland-build"
```

An optional second argument supplies a directory containing the four exact
archives, with the same SHA256 checks. The build directory must not exist.
Artifacts are under `install/`; source receipts, package inventory and each
stage's output are under `log/`. Errors preserve their exit status and logs.
The explicit private rpath and build-time pkg-config paths select this Mesa
and libdrm. Record actual loaded paths again during runtime validation.

On 2026-10-06 the final native build passed Mesa's 81 tests, labwc's three
tests and three libdrm tests, with one libdrm device-dependent skip. wlroots
defines no tests in this configuration. A separate EGL probe passed 64
allocate/render/readback cycles with every pixel checked using softpipe,
including normal context destruction and process exit. The tested loaded
EGL, GLES, GBM and libdrm paths all belonged to this private prefix.

The pkgsrc Mesa adaptations require `HAVE_NOATEXIT`: otherwise unload of a
DRI module leaves exit callbacks pointing into unmapped code. The recipe
sets that flag. A run without it crashed at process exit; the final build
completed normally. These results establish software plumbing only.

## seatd keyboard restoration probe

The separate `build-seatd.sh` stages seatd 0.9.3 (MIT) without modifying the
installed package. Its original archive URL and SHA256 are in
[`seatd-source.tsv`](seatd-source.tsv), and its SHA512 was checked against
the same pinned pkgsrc revision. Two pkgsrc patches are retained unchanged;
`patch-wscons-keyboard-restore` is a local AI-assisted follow-up, not submitted
upstream.

The pkgsrc terminal patch selects `WSKBD_RAW` when restoring the text
console. For NetBSD USB keyboards that mode emits compatibility PC/AT
bytes, bypassing wscons key events. libopeninput consumes wscons events,
so both its active input and restored console need `WSKBD_TRANSLATED`.
Exclusive access to `/dev/wskbd*` suppresses normal console delivery while
the compositor owns input. Simply swapping RAW and TRANSLATED would break
the active compositor's keyboard path.

```sh
sh build-seatd.sh "$HOME/.cache/emberbsd-seatd-build"
```

The test compiles the real patched `terminal.c`, replacing only its ioctl
boundary, and checks both mode transitions and error propagation. It failed
against the pkgsrc-only source and passed with the local patch. All three
upstream seatd tests also passed on NetBSD/aarch64. Actual USB keyboard,
VT switching and crash recovery still need a native session test.

The staged prefix is `stage/usr/pkg`; no binary is made setuid. For the
experimental runtime installation, an administrator should retain the
packaged `/usr/pkg/bin/seatd` and install only the staged `bin/seatd` there,
owned by root with mode 0755. The existing packaged `seatd-launch` already
starts that path and drops privileges before launching the compositor.
Keep the packaged libseat and launcher. Restore the saved daemon to undo
this local package-file change; a package upgrade may overwrite it.

## NetBSD absolute pointer input

The packaged libopeninput 1.30.2 wscons backend ignores absolute X/Y events,
and its four absolute coordinate accessors return -1. QEMU's USB Tablet
therefore produces clicks while the Wayland cursor remains at its origin.
The separate `build-libopeninput.sh` builds a private library with the same
`libinput.so.10` ABI; it does not replace the packaged library.

[`libopeninput-source.tsv`](libopeninput-source.tsv) pins the original
sizeofvoid/libopeninput archive at `dcf8584ec3f5cde2a2098de25276242d2d815cc7`,
including its URL and SHA256. Its bytes also match the pinned pkgsrc SHA512.
The original MIT/Expat license and source notices are retained. The two
`patch-src_wscons.*` patches are unchanged imports from the same pkgsrc
revision as the graphics probe. `patch-wscons-absolute-pointer` is a local
AI-assisted adaptation, not submitted upstream.

```sh
sh build-libopeninput.sh "$HOME/.cache/emberbsd-libopeninput-build"
```

Dependencies come from the existing pkgsrc environment: meson, ninja-build,
libudev-bsd, input-headers and libepoll-shim. Meson and upstream generators
require Python; the recipe and regression helper use shell and C. An optional
second argument supplies the original archive locally, with the same hash
check. Builds require a new absolute directory and an ordinary user.

The patch obtains raw HID bounds through `WSMOUSEIO_GCALIBCOORDS`. It supports
uncalibrated absolute devices with valid X/Y bounds and
`WSMOUSE_CALIBCOORDS_RESET`; calibrated touchscreens are outside this probe.
Adjacent axes are combined before a button event or at the end of each read.
Transformed accessors scale the coordinates to the compositor's output.
Wscons supplies no physical resolution: untransformed accessors use a
one-unit fallback, so their values are not measured physical millimetres.
Relative mouse events keep their existing acceleration path.

On 2026-10-06 the complete native build and the production-code regression
passed on NetBSD 11/aarch64. The regression failed against the pkgsrc-only
source because no absolute motion was emitted. It links actual upstream
objects, substitutes the calibration ioctl and feeds wscons events through
the real dispatch function. It checks all four accessors, nonzero minima,
axis retention, endpoints, motion before buttons, invalid or unsupported
calibration and relative fallback. The upstream Linux input tests are
disabled, as in pkgsrc; this is not a claim that their suite passed.

For the native session, prepend this build's `install/lib` to the existing
private graphics `LD_LIBRARY_PATH`. Confirm the compositor's loaded library
path and test motion, clicking and input in a fresh session separately.
The keyboard mapping is unchanged: a live trace showed correct press and
release events for ordinary letters, Shift and Return.

## Validation boundary

The helper runs the available upstream test suites. libdrm's `drmdevice`
test can legitimately skip when no DRM device is attached; a skip is not
a successful GPU test. Native input, VT handoff, scanout, buffer sharing,
VirGL pixel readback and reboot recovery must be checked separately.

Xwayland and Vulkan are initially disabled to isolate native Wayland and
classic VirGL. Optional libliftoff is disabled: the available binary links
base libdrm.so.3 while this private build provides libdrm.so.2. Loading both
would mix the DRM stacks. wlroots retains its built-in KMS plane handling.
This probe does not provide a GNOME Wayland port or a new
display manager. See the OS's
[VirtIO-GPU design](https://github.com/apovalixin/EmberBSD/blob/main/ember/boot/utm-virgl-design.md)
for the staged runtime acceptance checks.
