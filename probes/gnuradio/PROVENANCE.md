# GNU Radio source provenance

[GNU Radio 3.10.12.0](https://github.com/gnuradio/gnuradio/releases/tag/v3.10.12.0)
and [spdlog 1.17.0](https://github.com/gabime/spdlog/releases/tag/v1.17.0)
were the latest stable upstream releases checked on 2026-10-07.
[sources.tsv](sources.tsv) pins their official tag archives by SHA256.
GNU Radio retains its GPL-3.0-or-later license and upstream authorship;
spdlog retains its MIT license and Gabi Melman/contributor copyright.

Three patches are copied unchanged from NetBSD pkgsrc revision
[`fff4deb639a1a640476203c80f752fb77b6cb14b`](https://github.com/NetBSD/pkgsrc/tree/fff4deb639a1a640476203c80f752fb77b6cb14b/ham/gnuradio-core/patches).
[patches.tsv](patches.tsv) pins their hashes. Original `$NetBSD` identifiers,
explanations and upstream references are preserved.

- `boost-no-system.patch`: `patch-cmake_Modules_GrBoost.cmake`, revision 1.1,
  adam, 2025-09-27. Stops requiring a separate modern Boost.System library.
- `export-boost-no-system.patch`: `patch-cmake_Modules_GnuradioConfig.cmake.in`,
  revision 1.1, gdt, 2025-10-21. Applies the same dependency correction to installed
  consumer configuration; records upstream issue 7949.
- `install-differentiator-taps.patch`:
  `patch-gr-filter_include_gnuradio_filter_CMakeLists.txt`, revision 1.1, adam,
  2025-02-27. Retains the interpolating differentiator coefficient header in the
  installed interface. The installed consumer checks its presence.

`netbsd-runtime-librt.patch` is an original AI-assisted EmberBSD portability
change to GNU Radio's `gnuradio-runtime/lib/CMakeLists.txt`. NetBSD 11 supplies
`shm_open` and `shm_unlink` in `librt`, not libc. The unmodified target leaves
these symbols unresolved and fails when linking `gnuradio-config-info`.
The patch adds a private `rt` dependency only on NetBSD. The original failed
link and corrected link form the regression, and the installed check requires
`librt` in the runtime's ELF `DT_NEEDED` entries. This patch has not been
submitted to or accepted by upstream.

The profile reuses FFTW 3.3.11 and VOLK 3.3.0 from the sibling source profiles,
including their source receipts and patches. Shared fmt 12.2.0 comes from that
same VOLK prefix. spdlog explicitly uses external fmt; its bundled fmt copy is
not built. Existing common image packages Boost 1.91.0 and GMP 6.3.0 are used,
not installed, downgraded or duplicated by the helper.

Upstream GNU Radio's build generators still require Python. The tested image
provides Python 3.13.14, Mako 1.3.12 and packaging 26.2. Python bindings,
Companion, GUI, hardware radios, optional post-install actions and examples are
disabled in this profile. These switches do not remove upstream's build-time
Python requirement. No project-owned Python helper is introduced.
The optional libsndfile discovery is disabled explicitly. WAV file blocks and
their transitive audio codec dependencies are outside this C++ radio/FFT profile.

The shell, CMake and C++ contracts are original AI-assisted EmberBSD work under
the MIT license. Copied upstream patches retain their source attribution and
the licensing of the affected GNU Radio files. The three pkgsrc patches are
not claimed as EmberBSD work. The original portability patch retains GNU
Radio's licensing; none of these patches is claimed as upstream-accepted.
