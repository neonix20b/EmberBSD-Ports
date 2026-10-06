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
