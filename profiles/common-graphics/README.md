# Common graphics source packages

This opt-in source profile prepares canonical MesaLib 26.2.4 and adapted
libdrm 2.4.134nb1 for native NetBSD 11/AArch64. It composes the existing
[common build tools](../common-build-tools/README.md): GCC16, Python3.14.8,
Meson1.12.1 and shared LLVM23.1.2 remain one dependency graph with final
`LOCALBASE=PREFIX=/usr/pkg`. Plasma Mobile uses this exact graphics layer.
The default, development-toolchain and common-build-tools exports keep their
original Mesa/libdrm recipes. This is source preparation, not an installed
common graphics stack, native package acceptance or a Mobile demonstration.

The [graphics cross-build](cross/README.md) now builds the complete selected
libdrm payload on macOS with GCC16. All 26 staged entries match PLIST, and
hash, drmsl and symbol checks pass in AArch64 UTM. Device enumeration is
skipped on the current framebuffer-only kernel. Package registration and
the Mesa/LLVM consumer transition are still separate gates.

The selected APIs are X11/Wayland, EGL, GBM, OpenGL and GLES; renderers are
classic VirGL, softpipe and llvmpipe with ORC JIT. The recipe requires shared
LLVM23, upstream tests and portable TLS. It never substitutes Mesa21,
libLLVM13, another Python or native X11 GL/EGL/DRM/GLU providers. Native X11
protocol libraries can still satisfy pkgsrc's actual version checks.

## Prepare and select

```sh
sh scripts/prepare-pkgsrc.sh /absolute/new-pkgsrc common-graphics
# Plasma also replaces the current Qt/KF toolkit recipes:
sh scripts/prepare-pkgsrc.sh /absolute/another-new-pkgsrc plasma-mobile
```

Include the exported files in a private native MAKECONF, in this order:

```make
.include "/absolute/prepared-pkgsrc/EMBERBSD-COMMON-TOOLS-MK.CONF"
.include "/absolute/prepared-pkgsrc/EMBERBSD-COMMON-GRAPHICS-MK.CONF"
# For Plasma, include media before the toolkit:
.include "/absolute/prepared-pkgsrc/EMBERBSD-COMMON-MEDIA-MK.CONF"
.include "/absolute/prepared-pkgsrc/EMBERBSD-PLASMA-TOOLKIT-MK.CONF"
```

The exporter validates both source pins, complete recipe trees and exact
RCS-filtered patch hashes before creating its destination. It replaces only
`graphics/MesaLib` and `x11/libdrm` inside the new pinned pkgsrc export.
`EMBERBSD-COMMON-GRAPHICS-SOURCES` records their provenance. Unknown modes,
existing destinations and category collisions remain errors. No system
configuration or installed package is changed by preparation.

GCC selection belongs to the included common-tools configuration, including
the complete compiler package's runtime policy and native bootstrap boundary.
The graphics profile adds no second compiler policy.

The profile rejects conflicting command-line providers, dependency minima,
Meson overrides, old/unprepared recipes, cross builds, another platform or
prefix. Mesa substitutes one absolute common `PYTHONBIN` into upstream's
actual interpreter list, preserving version and Mako/packaging/PyYAML checks.
Failed imports cannot select another interpreter. LLVM's explicit absolute
`LLVM_CONFIG_PATH` reaches Meson's native file and environment; production
pre-configure checks reject missing metadata, another version, static-only
LLVM or missing ORC components/RTTI. There are no fallback downloads.

## Bounded package contents

Mesa enables zlib/zstd and the NetBSD libudev-bsd provider. Display-info,
libunwind, valgrind, Vulkan, video frontends, Rusticl/OpenCL, physical drivers,
OSMesa, XA and GLVND are outside this candidate. Requests for unsupported
Mesa options fail; they do not install older providers. Unselected optional
libelf/Lua/XCB-keysyms are absent from the buildlink sandbox.

libdrm is deliberately core-only. Intel, Radeon, AMDGPU, Nouveau, VMware and
physical ARM client modules, man pages and test-program installation are
disabled; upstream tests remain enabled. Unconditional kernel UAPI headers
remain installed. A consumer requiring `libdrm_amdgpu`, `libdrm_intel` or
another disabled client module is a migration blocker. Adapted revision
`nb1` prevents an unpatched libdrm2.4.134 package satisfying the native
identity requirement. The canonical recipe omits pkgsrc's native-X11
avoid-duplicate skip, so actual dependency selection still builds libdrm.

Mesa's PLIST is **source-derived and unvalidated natively**. The libdrm list
matches the complete cross-staged payload; normal package checks remain.
Mesa's GL/EGL/
GLES/GBM/DRM SONAME closure is GL1/EGL1/GLESv1_CM1/GLESv2 2/GBM1/DRM2,
plus `libgallium-26.2.4.so`, the GBM backend and upstream dril driver links.
`glx.pc`, `eglext_angle.h`, `gbm_backend_abi.h` and both upstream drirc
configuration defaults are included. Defaults remain in `share/drirc.d`;
an existing user drirc must be preserved independently. OSMesa/XA, video,
physical aliases and the old shared libglapi files are removed from PLIST.
Mesa26 shared-glapi is private/static within gallium, with no replacement DSO.

Normal same-pkgbase upgrade handles old Mesa-owned files. Separate installed
`libglapi`/`libglvnd` providers conflict explicitly; these are package-database
conflicts, not invented recipes in this pkgsrc pin. Never delete base X11
files or fabricate SONAME links. Native transition requires an ownership and
reverse-dependency inventory and actual rebuild of GLU, libepoxy, Qt/KF,
compositor and all installed/dynamically loaded graphics consumers.

## Provenance and verification

The recipe base is pkgsrc `fff4deb639a1a640476203c80f752fb77b6cb14b`.
[sources.tsv](sources.tsv) records original URLs and SHA256; distinfo also
records BLAKE2s, SHA512, size and filtered patch SHA1. Original RCS identifiers,
ownership and licences are retained. Local work is AI-assisted and has not
been submitted or accepted upstream.

The three exact accepted Mesa patches and the complete 44-patch disposition
belong to [the source probe](../../probes/wayland-utm/mesa-patches.md).
The package-only explicit-Python patch is the sole additional Mesa delta.
All seven imported libdrm patches plus the three accepted symbol/identity/
strict-warning patches remain byte-identical to
[their owner](../../probes/wayland-utm/native-identity.md). Disabled-module
patch hunks remain for provenance; their presence does not imply those modules
were built. The only unsupported-bus warning exception remains the narrow
`-Wno-error=cpp` used by the accepted strict-warning adaptation.

Run lightweight source checks with existing BSD make, Ruby, a C compiler,
OpenSSL with BLAKE2s, shasum, tar and patch:

```sh
sh profiles/common-graphics/tests/source.sh VERIFIED_DISTFILES NEW_WORK
sh profiles/common-graphics/tests/export.sh NEW_WORK
BMAKE=/absolute/bmake sh profiles/common-graphics/tests/profile.sh EXPORTED_PKGSRC NEW_WORK
BMAKE=/absolute/bmake sh profiles/common-graphics/tests/qtbase-egl.sh QTBASE_MAKEFILE NEW_WORK
BMAKE=/absolute/bmake sh profiles/common-graphics/tests/selection.sh \
    EXPORTED_PLASMA_PKGSRC NEW_WORK
TEST_PYTHON=/absolute/host-python3.14 TEST_MESON=/absolute/meson-1.12.1/meson.py \
BMAKE=/absolute/bmake ruby profiles/common-graphics/tests/configuration.rb \
    PATCHED_MESA NEW_WORK
```

For the final command, supply verified upstream Mako/MarkupSafe source paths,
packaging and PyYAML through `PYTHONPATH` when the host lacks them. No helper
installs packages. Its actual Meson fragment executes production interpreter
selection and upstream option declarations. Production recipe LLVM guards
use explicit metadata fixtures. Full-recipe selection executes pkgsrc's real
builtin/buildlink/dependency logic, using the exact pinned pkgtools dewey
matcher with narrow host header glue and declared target/installed-option
metadata. These host checks are not native Mesa configuration or compilation.
They retain host-only dlopen/license premises as failures, not fake success.
Upstream megadriver installation executes against dummy staging to verify
real relative link targets and master retention; it is not native staging.

Accepted lifetime/half-float/libdrm-identity contracts are referenced, not
rerun as package evidence. The new checks cover archive/patch integrity,
zero-fuzz once-only applications, import/tool failures, provider/version
selection, export composition and temporary-archive failure cleanup.

## Native acceptance remains mandatory

Accept the common Python/Meson/LLVM23 installed packages first. Build libdrm
and Mesa once with upstream tests in an isolated final-prefix package root.
Resolve both source-derived PLISTs against actual DESTDIR contents with normal
`check-files`, package, shared-library/RPATH/WRKREF and installed pkg_admin
checks. No skip list exempts a file from this gate.

Then rebuild and inspect affected consumers, including loaded dril/GBM/Qt
plugins: exactly one Mesa/DRM/sharedLLVM/GCC16 runtime, no libglapi, old base
GL3/EGL0/DRM3, build paths or loader overrides. NetBSD clients loading worker
libraries need pthread at process startup. Real softpipe/llvmpipe/ORC lifecycle
and graphics checks, matched-kernel KMS/input identity and VirGL sessions
remain runtime gates. The [common media profile](../common-media/README.md) prepares FFmpeg9 for
Qt Multimedia/KFileMetadata; native packages and playback remain unaccepted. Physical boards, full graphics acceleration and the complete
Mobile workflow remain unverified.
