# labwc 0.20.2 cross-package work in progress

**Work in progress:** the recipe and selection checks are prepared.
The first ordinary configuration failed at the librsvg dependency.
No labwc package, installation or target session is accepted by this stage.
Work stopped at the user's requested checkpoint before another configure run.

The `labwc-0.20.2nb2` recipe targets the shared wlroots 0.20.2,
Mesa 26, LLVM 23, GLib 2.90.1 and librsvg 2.63.2 stack. It retains the
compositor, labnag, terminal/session helpers, SVG window decorations,
freedesktop icons, translations, configuration examples and man pages.
EmberBSD Ports owns the recipe and cross-build checks. A working desktop
session requires separate target acceptance.

The upstream [0.20.2 release](https://github.com/labwc/labwc/releases/tag/0.20.2)
was current on 2026-10-09. Its
[archive](https://github.com/labwc/labwc/archive/0.20.2.tar.gz) has SHA256
`fae023b6fe022f7057556707a17cdb2d98e0138c5dffaedaa1dade975699f9e8`.
It also matches the pinned pkgsrc SHA512 and size. The recipe is imported
from pkgsrc `fff4deb639a1a640476203c80f752fb77b6cb14b`, preserving its
authors and three existing patches. EmberBSD's changes are AI-assisted and
have not been submitted upstream.

## Build selection

Use the [common graphics cross profile](profile.md), accepted
[Wayland scanner](wayland.md), [wlroots package](wlroots-package.md),
[text dependencies](labwc-dependencies.md), [desktop support](desktop-support.md)
and current [librsvg package](librsvg.md). Reuse their installed providers;
this recipe does not need a second compiler, GLib or graphics stack.
Keep the [sysroot provenance](../../common-build-tools/cross/sysroot.md)
with the build. A successful package does not certify the entire base sysroot.

Upstream requires wlroots >=0.20.1 and <0.21.0, Wayland >=1.22.90,
wayland-protocols >=1.39 and, for the enabled input backend, libinput >=1.26.
The common stack supplies the accepted libopeninput 1.31.3 implementation
of that API. The recipe requires wlroots 0.20.2nb4 or newer within the
selected upstream range.

The current accepted wlroots DRM/GLES2 configuration has no Xwayland.
Select this matching Wayland-only variant explicitly in private MAKECONF:

```make
PKG_OPTIONS.labwc= -xwayland
```

The public recipe still suggests the `xwayland` option. Selecting it requires
Xwayland, xcb-util-wm and a wlroots provider built with Xwayland support.
Missing providers fail configuration. This avoids upstream's silent fallback
from its automatic Xwayland setting. X11 application migration remains a
separate stage and is not established by the Wayland-only package.

SVG, icons, labnag, native-language support and man pages are required.
A small upstream Meson correction makes an explicitly enabled SVG feature
fail when librsvg is absent. The explicit disabled SVG path remains valid.
Subproject fallback downloads are disabled. The existing systemd-session
feature remains automatic; EmberBSD does not provide systemd.

Cross builds use the accepted host scanner and its verified installation
receipt. Native scdoc and msgfmt produce the man pages and translations.
Target executables are not build generators. The native recipe does not
inherit these cross tool paths. Build with a new work directory, an external
temporary directory and the ordinary pkgsrc targets:

```sh
bmake -C /path/to/exported-pkgsrc/wayland/labwc \
  MAKECONF=/path/to/private/mk.conf package install
```

The standard cross installation destination is the private sysroot.
It does not install or start a compositor on a VM or physical board.

## Focused checks

Run from `profiles/common-graphics` with new absolute work directories:

```sh
ruby tests/labwc-cross.rb /path/to/labwc-0.20.2.tar.gz \
  /path/to/native-prefix /path/to/new-feature-check
BMAKE=/path/to/native-prefix/bin/bmake ruby tests/labwc-options.rb \
  /path/to/exported-pkgsrc /path/to/private/mk.conf /path/to/new-options-check
ruby tests/labwc-package.rb /path/to/labwc-0.20.2nb2.tgz \
  /path/to/sysroot /path/to/cross-tools/bin/aarch64--netbsd-readelf \
  /path/to/built/labwc-0.20.2 /path/to/new-package-check
```

The feature regression checks the archive and patch hashes, applies the
patches without fuzz, reproduces the original silent SVG omission and
checks the corrected enabled/disabled behavior with actual Meson.
The option check evaluates the actual pkgsrc recipe for native and cross
builds, including both Xwayland selections and missing-scanner rejection.
The package check compares every installed payload file with the archive,
checks the configured features and inspects the target ELF dependency closure.
Static ELF inspection does not prove which providers a target process loads.

The source/feature and recipe-option checks passed. The package inspection
helper has only passed a Ruby syntax check; it has not run on a labwc package.
The recipe has not yet been added to the shared exporter/source registry;
the current `common-graphics` export does not include this labwc overlay.

## Checkpoint and continuation

The first ordinary `bmake configure` found the selected wlroots, Wayland,
GLib, Cairo, Pango and input providers. It stopped with:

```text
Package 'dav1d', required by 'librsvg-2.0', not found
ERROR: Dependency lookup for librsvg-2.0 with method 'pkg-config' failed
```

The installed librsvg 2.63.2 metadata declares dav1d in `Requires.private`.
Dav1d is installed in the sysroot, but the then-current
[librsvg buildlink recipe](../recipes/graphics/librsvg/buildlink3.mk)
did not expose it in a downstream package's `.buildlink` metadata directory.
The correction belongs to librsvg: admit its selected AVIF dependency using
the installed package options. Adding a private search path to labwc would
conceal the incomplete dependency declaration.

The librsvg owner has prepared the conditional AVIF buildlink correction in
the public recipe and working pkgsrc copy. This labwc checkpoint does not
claim a successful configure after it. To continue, verify that correction
in the exported recipe, retain the failed work/log as evidence, select a new
work directory and rerun ordinary `configure`, then `package install`.
Keep `PKG_OPTIONS.labwc=-xwayland` with the current accepted wlroots provider.
For example, extend the existing private cross configuration:

```make
.include "/path/to/private/mk.conf"
WRKOBJDIR=/absolute/new-labwc-work
MAKE_JOBS=1
PKG_OPTIONS.labwc= -xwayland
```

Save that as a new MAKECONF and run:

```sh
TMPDIR=/absolute/external-tmp bmake \
  -C /path/to/prepared-pkgsrc/wayland/labwc \
  MAKECONF=/path/to/private/labwc-next.mk.conf configure
TMPDIR=/absolute/external-tmp bmake \
  -C /path/to/prepared-pkgsrc/wayland/labwc \
  MAKECONF=/path/to/private/labwc-next.mk.conf package install
```

The prepared pkgsrc tree must contain this WIP overlay and the corrected
librsvg buildlink recipe. The new work directory makes ordinary pkgsrc
regenerate buildlink metadata and wrappers. The installed current libraries
are reused; rebuilding librsvg, dav1d or the compiler is not the required fix.
Run the package inspection helper only after successful packaging and private
sysroot installation. Missing NetBSD portability/link dependencies may still
surface during compilation; the current checkpoint has not tested them.

The normal upstream test option remains disabled. Client surfaces, EGL
presentation, screen capture, real keyboard/pointer events and clean repeated
sessions require the separate VM scenario. None of these package checks
establishes hardware GPU acceleration.
