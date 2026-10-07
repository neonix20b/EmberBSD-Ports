# Common Qt and Frameworks source candidate

This layer prepares **Qt 6.12.0 LTS** and **KDE Frameworks 6.30.0** for the
common GCC 16 / LLVM 23 userspace migration. It extends the existing
[common build-tools profile](../../../profiles/common-build-tools/README.md).
It does not install another Qt prefix for Plasma. Final package paths remain
`/usr/pkg` and `/usr/pkg/qt6` inside the common staging environment.

**Source checks pass; native packages and the Plasma Mobile session are not
accepted.** In particular, the inherited PLISTs still require native staging
and `check-files`. This export is not a command to upgrade an active desktop.
See the [migration sequence](MIGRATION.md) and the
[actual Mobile graphics contract](../kwin/MOBILE-GRAPHICS-CONTRACT.md).

## Prepare the source tree

```sh
git submodule update --init --depth 1 upstream/pkgsrc
sh scripts/prepare-pkgsrc.sh /absolute/new-pkgsrc plasma-mobile
```

The new export contains the unchanged common Python/Meson/LLVM family and
development-toolchain recipe deltas, followed by this toolkit layer. The
default, `development-toolchain` and `common-build-tools` modes retain their
previous selection. No existing pkgsrc directory is overwritten.

The toolkit includes 22 Qt modules and all 68 Frameworks recipes present
in the pinned pkgsrc, plus Extra CMake Modules. Their original recipes come
from pkgsrc `fff4deb639a1a640476203c80f752fb77b6cb14b`. The shared version files
reject older command-line versions and unprepared Qt/Frameworks recipe paths.
Buildlink requirements select the new versions, including transitive consumers.
Qt's common build and consumer files require GCC 16.2.

For a later native build, a private MAKECONF includes the exported
`EMBERBSD-COMMON-TOOLS-MK.CONF` and then
`EMBERBSD-PLASMA-TOOLKIT-MK.CONF`. The latter selects GCC 16.2, one worker and
release compiler flags without changing `/etc/mk.conf`. It refuses inherited
FFmpeg8 consumers until their common FFmpeg9 integration is ready, requires
Mesa26.2.4 and disables the built-in X11 GL/GLU fallback. The native dependency
closure must be prepared first as described in MIGRATION.md.

## Provenance and patch decisions

Original pkgsrc RCS identifiers, recipe ownership, upstream licences and
patch explanations are retained. The manifest and adaptations are
AI-assisted EmberBSD work; these changes have not been submitted or accepted
upstream. [sources.tsv](sources.tsv) records original archive URLs and SHA256.
Qt hashes were compared with the official `.sha256` responses. KDE archive
hashes were recorded from the upstream HTTPS downloads; this is not a claim
of release-signature verification. The recipes also record BLAKE2s, SHA512,
size and pkgsrc's RCS-filtered patch SHA1.

| Imported patch | Decision for the current toolkit |
| --- | --- |
| QDoc supported-Clang list | Drop: Qt 6.12 already names Clang 23.1 and 22.1. |
| QDoc QualTypeNames include workaround | Drop: Qt's vendored implementation now contains the LLVM 22+ API adaptation and its QDoc-specific behavior. |
| Qt icon theme fallback | Drop: upstream change 763319 is present in the archive. |
| Eight KCodecs `std::format` replacements | Drop: these only compensated for GCC 12. The current profile requires GCC 16 and retains upstream C++20. Native KCodecs checks are still required. |
| Qt syncqt build ordering | Refresh context around the additional generated documentation headers; preserve the pkgsrc dependency. |
| Qt archive-API configure switch | Refresh context; preserve the pkgsrc libarchive workaround. |
| Qt NetBSD thread naming | Refresh context around the VxWorks addition; preserve the NetBSD signature. |
| Qt Quick Test Solaris linker option | Refresh context around the Android target block. |
| Qt audio temporary buffer | Refresh context around the upstream nonblocking annotation; retain the NetBSD alloca branch. |
| Qt FFmpeg VAAPI linkage | Link VAAPI directly on platforms where the Linux/Android stub helpers are unavailable, even when FFmpeg metadata lists `va`. Preserve Linux/Android stub selection. |

The remaining pkgsrc patches apply to the verified sources with zero fuzz.
Retaining a portability patch does not establish runtime support for every
platform mentioned by it. No upstream source archive or binary is stored here.

## Reproduce the source checks

Download the original archives listed in sources.tsv to a private directory.
The checks require BSD make, CMake, tar, patch, shasum and OpenSSL with
BLAKE2s support. Set `BMAKE`, `CMAKE` and `OPENSSL` when necessary.

```sh
sh probes/plasma-mobile/toolkit/tests/source-profile.sh \
    /absolute/verified-distfiles /absolute/new-source-check
```

The check covers all 91 archives, 77 patch hashes and forward applications,
corrupted archive rejection, repeated/missing patch rejection, incorrect
unfiltered RCS hashes, recipe/version selection and exact toolkit export.
It compares the exported common recipes and configuration with their existing
owners without repeating their previously accepted source contracts.

`tests/selection.sh TOOLKIT NEW_WORK` executes the production selection blocks
with BSD make. External pkgsrc includes are omitted; it does not replace full
native recipe parsing. It allows the 90 shared-version recipes and rejects
four unprepared recipes and two old version overrides.

`tests/ffmpeg-vaapi.sh PATCHED_QTMULTIMEDIA NEW_WORK` executes the production
CMake VAAPI branch for six platform/metadata combinations. Target creation
is recorded by the fixture; no native library or multimedia playback is
claimed. The original non-Linux `va` branch calls an unavailable stub helper.

`tests/dependencies.sh NEW_WORK` checks those pending dependency rejections
and the Mesa version/built-in-library constraints through actual BSD make.
`tests/export-lifecycle.sh NEW_WORK` performs successful and injected-failure
exports, checking temporary-archive cleanup and preservation of a caller-owned
archive with the same name as a toolkit distfile. It needs space for two exports.

Package manifests, installed tools, QDoc with real LLVM 23, Qt plugins,
Wayland/OpenGL, codecs, and the complete Mobile workflow remain native gates.
