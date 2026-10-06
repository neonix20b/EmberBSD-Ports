# awesomeWM source probe provenance

Sources were retrieved from their original upstream locations on 2026-10-07.
[source.tsv](source.tsv) records archive names, SHA256 values and URLs.
Original archives and binaries are not committed to this repository.

- awesomeWM 4.3: the [official download page](https://awesomewm.org/download/)
  and [latest release](https://github.com/awesomeWM/awesome/releases/latest)
  identified 4.3 as stable when checked. The selected release archive is
  published under tag `v4.3`, commit `5da5d36`.
- LGI 0.9.2: the [upstream tags](https://github.com/lgi-devs/lgi/tags)
  identified 0.9.2 as the latest tagged release. Its tag resolves to
  `0fdcf8c677094d0c109dfb199031fdbc0c9c47ea`. The archive is from GitHub's
  codeload service for the upstream repository, formerly `pavouk/lgi`.
- Lua 5.4.6 is supplied by the target operating system. The recipe does
  not download or install an interpreter. Installed headers and library
  are checked together before building either consumer.

## Patches

1. `patches/lgi/0001-lua54.patch` is Uli Schlachter's accepted upstream
   [commit 5cfd42c](https://github.com/lgi-devs/lgi/commit/5cfd42c386d3adae6d211fbb4011179c3c141b04).
   It adapts `lua_resume` to the Lua 5.4 API. The original patch and
   authorship header are preserved; it applies to 0.9.2 with line offsets.
2. `patches/lgi/0002-glib-require.patch` and `0003-glib-enums.patch` are
   copied unchanged from `devel/lua-gi/patches` in the repository's pinned
   [pkgsrc revision fff4deb](https://github.com/NetBSD/pkgsrc/tree/fff4deb639a1a640476203c80f752fb77b6cb14b/devel/lua-gi).
   They preserve their NetBSD identifiers. Their headers reference upstream
   [commit 5233d837](https://github.com/lgi-devs/lgi/commit/5233d837046988296b1b442ecb269b4be91e0b7f)
   and [pull request 352](https://github.com/lgi-devs/lgi/pull/352).
   The first asserts successful namespace resolution. The second also
   adapts enum loading to GLib 2.87's introspection annotation changes.
   The copied patches' stated provenance is retained; their presence in
   pkgsrc is not a claim that every referenced change was merged upstream.
3. `patches/awesome/0001-gcc10.patch` backports Reiner Herrmann's accepted
   [commit d256d905](https://github.com/awesomeWM/awesome/commit/d256d9055095f27a33696e0aeda4ee20ed4fb1a0).
   It moves variable definitions out of headers for GCC's `-fno-common`
   default. Context in `luaa.c` and `objects/tag.c` is adjusted for 4.3;
   the code changes and original authorship header are preserved.
4. `patches/awesome/0002-build-tools.patch` is an AI-assisted EmberBSD
   adaptation. It selects the Lua interpreter explicitly for generated
   configuration files and avoids a missing documentation target when
   API documentation is disabled. The latter follows the problem already
   addressed by pkgsrc's `wm/awesome/patches/patch-CMakeLists.txt`, while
   preserving example checks when the target exists. This local patch
   has not been submitted or accepted upstream.
5. `patches/awesome/0003-native-icons.patch` adds an optional dedicated
   converter for the two theme-icon operations. The upstream ImageMagick
   path remains the default outside this probe. The local patch and
   `theme-icon.c` are AI-assisted EmberBSD work, not submitted upstream.
6. `patches/awesome/0004-pthread-startup.patch` explicitly links both
   awesome and `lgi-check` with CMake's `Threads::Threads`. NetBSD initializes
   libpthread during libc startup; loading a threaded module later cannot
   make a non-threaded main program a supported pthread host. This local
   patch has not been submitted upstream. The OS-owned companion fix links
   the existing system Lua CLI with pthread; no second interpreter or
   permanent `LD_PRELOAD` is used.
7. `patches/awesome/0005-lua54-version.patch` restricts the LGI version
   query to one Lua result. Lua 5.4's `require` also returns loader data;
   retaining it shifts the stack-relative Lua and LGI version fields.
   The symptom is reported in upstream
   [issue 3563](https://github.com/awesomeWM/awesome/issues/3563).
   This minimal AI-assisted EmberBSD fix has not been submitted upstream.
   `tests/check-version.sh` checks the actual executable's Lua 5.4 and
   LGI 0.9.2 output. The change only affects `--version`, not WM startup.
8. `patches/awesome/0006-wm-selection-name.patch` applies the one-line
   correction documented by Uli Schlachter (psychon) in upstream
   [issue 3561](https://github.com/awesomeWM/awesome/issues/3561).
   `xcb_atom_name_by_screen` appends `_S<screen>`; passing `WM_S` produced
   `WM_S_S0` in a native library probe. The first shared X11 contract timed
   out waiting for the required `WM_S0` owner while awesome was running.
   Passing `WM` selects the correct ICCCM atom. The existing shared
   `x11-contract.c` selection-owner check remains the runtime regression.
   This local patch is AI-assisted and is not claimed as accepted upstream.

The full LGI contract originally aborted with `pthread_create` returning
`EOPNOTSUPP` (exit 134) under the unmodified system Lua. The same contract
passed with system libpthread preloaded as a diagnostic experiment.
NetBSD's `tests/lib/libpthread/dlopen/t_dso_pthread_create.c` explicitly
tests the unsupported non-pthread-main/threaded-DSO combination.
The recipe now requires startup pthread linkage and checks the built
executables, so it does not silently depend on the diagnostic preload.
On the native GCC 12.5/CMake 4.3.3 test, `FindThreads` rejected its libc-only
compile test and selected `-pthread`. A tiny executable linked through
`Threads::Threads` had `DT_NEEDED: libpthread.so.1` and successfully created
and joined a worker thread. No NetBSD-specific detection override is needed.
The builder verifies the executable ELF dependencies directly with
`readelf`, independently of CMake's detection result.

The icon helper uses GdkPixbuf and libm already needed by the graphical
stack. It accepts only the two operations and the release's 19x19 RGB
icons. The linear-sRGB transfer, gamma 0.6, alpha multiplier 0.4 and
grayscale luminance operations follow awesome's CMake commands.
Grayscale coefficients are verified against ImageMagick
[7.1.2-32 colorspace.c](https://github.com/ImageMagick/ImageMagick/blob/7.1.2-32/MagickCore/colorspace.c).
`tests/theme-icons.tsv` records SHA256 of row-major 8-bit RGBA pixels
generated by that host ImageMagick release from the verified awesome
archive. All 13 derived icon outputs compare byte-for-byte with the
reference decoded pixels. PNG container metadata is not part of this
comparison. No generated binary assets are committed.

`native-pkg-config.sh` is reused from EmberBSD's Enlightenment probe. It
selects the native gettext ABI used by the installed NetBSD GLib stack.
The builder's separate install prefix makes the experiment removable;
it is not a policy of shipping separate dependencies per application.

## Licenses and verification

`LICENSES/AWESOME` is copied unchanged from the awesomeWM release. Its
source files retain their individual authorship and GPL-2.0-or-later
notices. `LICENSES/LGI` is LGI's original MIT license. Existing upstream
and pkgsrc notices remain in source patches. The project-owned shell,
C and Lua helpers are AI-assisted EmberBSD work under BSD-2-Clause;
see `LICENSES/EMBERBSD-HELPERS`.

The preparation checks hashes, applicability of every patch and shell
syntax. Runtime and native build evidence must be recorded separately
before claiming a working desktop. The included LGI test specifically
exercises the changed coroutine API and the rendering libraries used
by awesome; it is not a complete LGI or awesome upstream test run.

NetBSD Lua does not include the current directory in its module search
path. The source builder adds the absolute build directory only to the
compile command, where upstream generators load docs._parser. Installed
runtime environments do not search the build directory.
