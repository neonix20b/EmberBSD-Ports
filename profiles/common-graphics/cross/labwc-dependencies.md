# Current text and image dependencies for labwc

This is the package-building stage for the common labwc stack. It uses the
accepted macOS-to-AArch64 tools and one target `/usr/pkg`. It does not establish
a working labwc session, text rendering on a target, or SVG support.
The accepted wlroots renderer and DRM scenarios remain documented in
[wlroots](wlroots.md) and [DRM/input](drm-input.md).

## Sources and composition

The profile exports current upstream recipes for GLib 2.90.1, PCRE2 10.49,
FriBidi 1.0.17, libpng 1.6.59, FreeType 2.14.3, HarfBuzz 14.6.0, Cairo 1.18.6
and LZO 2.10. Exact archive URLs and SHA256 hashes are in
[`sources.tsv`](../sources.tsv); pkgsrc checks the archives and patches again.
GLib's tools, D-Bus code generator and introspection recipe share its version.
They do not select an older GLib for build-host tools.

The pinned pkgsrc tree already supplies current Brotli 1.2.0, fontconfig 2.18.3,
Graphite 1.3.15 and Pango 1.58.2. Their unchanged recipes remain in that tree.
The required native gperf 3.3 and GLib Python tools use the existing common
host prefix. LLVM, Mesa, compilers and Python are reused.

Release checks use the upstream
[GLib index](https://download.gnome.org/sources/glib/2.90/),
[PCRE2 release](https://github.com/PCRE2Project/pcre2/releases/tag/pcre2-10.49),
[FriBidi release](https://github.com/fribidi/fribidi/releases/tag/v1.0.17),
[libpng announcement](https://libpng.org/pub/png/libpng.html),
[FreeType news](https://freetype.org/index.html),
[HarfBuzz release](https://github.com/harfbuzz/harfbuzz/releases/tag/14.6.0),
[Cairo releases](https://cairographics.org/releases/), and
[LZO's current release and published fix](https://www.oberhumer.com/opensource/lzo/).
The APNG option retains its matching 1.6.59 upstream patch and checksums.

## Cross-build changes

GLib's build-time Python is `TOOL_PYTHONBIN`; installed scripts retain the
normal target interpreter. Its portability patches are refreshed against the
exact 2.90.1 sources. The new upstream FreeBSD `environ` implementation is
preserved. The traffic-class test checks socket-option availability individually:
NetBSD's missing `IP_RECVTOS` does not disable its available IPv6 test.
Compilation does not establish that this IPv6 runtime test passes.

Cairo's Quartz and FreeType's Carbon selection now require target `OPSYS=Darwin`.
A framework directory on a macOS build host does not enable that target backend.
Native Darwin selection is unchanged. NetBSD's usual Cairo X11 backend remains
enabled. FreeType also receives the existing common profile's absolute build
compiler as `CC_BUILD`. Otherwise its empty pkgsrc `NATIVE_CC` let `gcc` resolve
to a target wrapper and produced an ELF `apinames` generator for the Mac.
The corrected build produces a real host executable and target libraries.

FriBidi explicitly declares its new `pkg-config` build requirement. Its release
archive includes `fribidi.1`; cross builds retain that exact page instead of
executing the target binary through `help2man`. An absent page fails. Native
generation keeps the original rule. The installed package includes the page.

LZO 2.10 remains the latest release. The profile applies its authors' published
one-byte LZO1F safe-decoder bounds fix, with attribution in the patch. The
regression reproduces the original heap overread under AddressSanitizer and
checks that the corrected decoder returns `LZO_E_INPUT_OVERRUN` with no output.
This is a native source-level check, not target runtime acceptance.

## Reproduction

Prepare the `common-graphics` export and use the composed cross configuration
described in [the cross-build guide](README.md). Select a new absolute work
directory, an existing shared distfile cache, and at most two build jobs.
Keep the recipe snapshot immutable during a build. Use the actual native
Python/Meson, accepted GCC16 tools, and current target sysroot.

Build ordinary pkgsrc `package` targets in dependency order: PCRE2, GLib,
FriBidi, PNG, FreeType, fontconfig, HarfBuzz, Cairo and Pango. pkgsrc resolves
the remaining normal prerequisites. Host-only `glib2-tools` and `gdbus-codegen`
use the same exported GLib family with `USE_CROSS_COMPILE=no`. Install packages
into the cross sysroot with its standard pkgsrc install command; do not suppress
dependency, PLIST, ELF, RPATH or work-reference checks.

When changing a configure input after a failed build, clean that package's
work before retrying. A package revision change alone need not invalidate a
partially completed configure stage. Preserve the failed log and causal artifact.
A PLIST-only correction can restage the already built files without changing
their compile flags.

Focused tests use real package parsing, generated upstream rules and source:

```sh
BMAKE=/path/to/host/bin/bmake ruby tests/cairo-cross.rb \
  /path/to/pkgsrc /path/to/cross.mk /path/to/new-cairo-check
BMAKE=/path/to/host/bin/bmake ruby tests/freetype-cross.rb \
  /path/to/pkgsrc /path/to/cross.mk /path/to/new-freetype-check
GMAKE=/path/to/host/bin/gmake ruby tests/fribidi-cross.rb \
  /path/to/built/fribidi-1.0.17 /path/to/new-fribidi-check
HOST_CC=/path/to/native/clang ruby tests/lzo-overread.rb \
  /path/to/lzo-2.10.tar.gz /path/to/new-lzo-check
sh tests/export.sh --preflight-only /path/to/new-export-preflight
```

Run these commands from `profiles/common-graphics`. The first two regressions
require macOS with its actual framework directories. Their original controls
reproduce the cross-selection errors, then check corrected target behavior and
unchanged native selection. The FriBidi check needs the completed target ELF;
it does not substitute a fake executable. Each test preserves inputs and logs.

## Acceptance boundary

On 2026-10-08, ordinary package creation and installation in the AArch64 cross
sysroot passed for the following stack. pkgsrc's PLIST, interpreter, permissions,
ELF, RPATH and work-reference checks remained enabled.

| Package | Version |
| --- | --- |
| PCRE2 | 10.49 |
| GLib | 2.90.1 |
| FriBidi | 1.0.17 |
| libpng | 1.6.59 |
| Brotli | 1.2.0 |
| FreeType | 2.14.3nb1 |
| fontconfig | 2.18.3 |
| Graphite | 1.3.15 |
| HarfBuzz | 14.6.0 |
| LZO | 2.10nb1 |
| Cairo | 1.18.6 |
| libXext / libXrender | 1.3.7 / 0.9.12 |

Native GLib generators and `gdbus-codegen` 2.90.1, plus gperf 3.3, also passed
normal pkgsrc package checks. The focused regressions above passed. Pango's
next dependency currently fails because the stock libXt recipe overwrites
`CC_FOR_BUILD` with empty `NATIVE_CC`, producing a target ELF `makestrs` tool.
This checkpoint does not disable Pango's X11 option to avoid that dependency.

These are build milestones. Target GLib/PCRE2 execution, font discovery, shaping,
rasterization and the eventual labwc client/compositor scenario require separate
acceptance. The matching APNG patch is retained, but this package run used the
unchanged default without APNG; it does not establish APNG runtime support.

The stock cross selections for introspection remain explicit. GLib 2.90.1
requires the ability to run target binaries when introspection is enabled.
Host Darwin introspection output is not target metadata. Full SVG also needs
the current librsvg provider and its accepted Rust/tooling closure. These are
not replaced with an older library or silently claimed complete here.
