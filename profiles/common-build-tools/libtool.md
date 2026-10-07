# Libtool 2.6.2

The common profile updates the pinned pkgsrc Libtool family to GNU Libtool
2.6.2. The same source release supplies the native target scripts and the
host-side cross Libtool used when building target shared libraries. GNU M4
1.4.21 is an explicit runtime dependency of installed `libtoolize`.

## Source and maintained patches

The original archive is downloaded from GNU; its URL and SHA256 are recorded
in [sources.tsv](sources.tsv). The exported recipe contains pkgsrc BLAKE2s,
SHA512, size and RCS-filtered patch SHA1 checksums. NetBSD pkgsrc identifiers,
authorship and licenses are retained. The refresh and target conversion are
AI-assisted EmberBSD changes, not submitted upstream.

Pkgsrc's maintained `manual-*` changes are refreshed against the current
source. Generated `configure`, `libltdl/configure` and `build-aux/ltmain.sh`
patches come from those maintained inputs. The update preserves pkgsrc's
platform behavior, shared-library naming, installed script layout and
Fortran/cross recipe composition. The Makefile installation-directory hunk
is applied to the current upstream rule.

Regeneration uses Autoconf 2.73 and Automake 1.18.1. Verify the exact generated
files rather than independently editing generated shell code:

```sh
PATH=/absolute/current-autotools/bin:$PATH \
DIGEST=/absolute/host/bin/digest \
sh profiles/common-build-tools/tests/libtool-source.sh \
    /absolute/export /absolute/distfiles /absolute/new-check
```

The gate verifies the archive and pkgsrc patch checksums, applies source and
manual series with zero fuzz, rejects repeated patch application and compares
regenerated configure/ltmain output byte for byte. This gate passed on macOS;
it does not substitute for installed target execution.

## Host and target scripts

Cross configure must execute on the Mac, but installed `libtool`,
`libtoolize` and `shlibtool` must run on NetBSD. The scoped recipe converts
configured host shell, sed, linker and compiler paths to target paths. It
uses the selected `/usr/pkg/gcc16` compiler and runtime, not a second ABI.
Unconverted known build directories fail the conversion.

The target `/bin/sh` has no mksh `print` builtin, so the configured echo
operation uses portable `printf`. `max_cmd_len` is 196608: NetBSD 11's 256 KiB
ARG_MAX with the upstream BSD three-quarter safety margin. Querying host
`sysctl` during cross configure cannot establish this target value.

The [cross package profile](cross/README.md) separates host and target
package metadata and preserves the target CRT choice through compiler
wrappers. `run-libtool-tests.sh` exercises installed C11/C++20 shared and
static consumers, exception handling through a DSO, loaded GCC16 libraries,
libtoolize macro installation, shlibtool and uninstall. Run it in an EmberBSD
AArch64 guest after ordinary `pkg_add` installation, with a new output path.
Fortran consumer execution remains outside this acceptance gate.
