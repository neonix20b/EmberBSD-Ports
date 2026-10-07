# VOLK source provenance

[VOLK 3.3.0](https://github.com/gnuradio/volk/releases/tag/v3.3.0) and
[fmt 12.2.0](https://github.com/fmtlib/fmt/releases/tag/12.2.0) were the latest
stable upstream releases checked on 2026-10-07.
[sources.tsv](sources.tsv) pins the official VOLK release archive and fmt tag
archive by SHA256. Neither CMake nor the build helper may fetch fallback sources.

VOLK retains its upstream LGPL-3.0-or-later license and all contributor
copyright notices. The release archive includes cpu_features 0.9.0 at revision
`ba4bffa86cbb5456bdb34426ad22b9551278e2c0`, covered by the same archive hash.
cpu_features retains its Apache-2.0 license, but is not compiled or linked here.
The current cpu_features 0.11.0 sources were also checked: their AArch64 backends
include Linux/Android, macOS/iPhone, FreeBSD/OpenBSD and Windows, not NetBSD.

This profile uses the upstream `VOLK_CPU_FEATURES=OFF` option only on native
NetBSD/aarch64. It does not fabricate a cpu_features implementation. VOLK's
generator already treats AArch64 NEON as a baseline capability; its `GetArmInfo`
query applies only to 32-bit ARM. The native compiler is restricted to
`-march=armv8-a`, and configuration must produce exactly the generic, neon and
neonv8 machines. The installed tests require neonv8 dispatch and actually execute
the available generic and NEON kernels. This is not runtime detection of optional
SVE, crypto or newer ARM extensions. Other architectures are rejected by the helper.

The two patches are copied byte-for-byte from NetBSD pkgsrc at revision
[`fff4deb639a1a640476203c80f752fb77b6cb14b`](https://github.com/NetBSD/pkgsrc/tree/fff4deb639a1a640476203c80f752fb77b6cb14b/math/volk/patches).
They retain the original `$NetBSD` identifiers and explanations. EmberBSD did
not author these fixes or claim their acceptance by VOLK.

- `patches/fmt-format-header.patch`: pkgsrc `patch-lib_qa__utils.cc`, revision
  1.1, wiz, 2026-06-25. VOLK calls `fmt::format`, which requires the explicit
  `fmt/format.h` include with fmt 12.2. The patch records
  [upstream issue 868](https://github.com/gnuradio/volk/issues/868).
  SHA256: `0d4b7f6ea56fe7ab9404c1a06cc198222796a1aa7cb0bfa517c4cca9654bb9ee`.
- `patches/netbsd-cxx-math.patch`: pkgsrc `patch-include_volk_volk__common.h`,
  revision 1.3, gdt, 2026-02-09. It selects `<cmath>` and standard C++
  classification functions while retaining `<math.h>` in C. The source comment
  records a report to upstream by email in February 2026.
  SHA256: `854ce553f95296bbc1aa5e3009c4d5a171ee2fde112fc98b2995f4b7b5018ab4`.

The unpatched C++ compilation failed in the actual `volk_common.h` after
`<cmath>` was included. The same source contract then passed with the pkgsrc
patch: 18 finite, NaN and infinity checks in both C17 and C++17. Installed
header regressions retain this include order. The older pkgsrc `tgmath.h`
workaround is not needed by this NetBSD 11 image and is not applied.

fmt retains its upstream MIT license. Its shared library, exported CMake target,
headers and pkg-config metadata are installed alongside VOLK for reuse by other
consumers. No old fmt 10.2.1 fallback is fetched or installed.

Upstream VOLK requires Python and Mako to generate its C headers and dispatch
tables. Mako also uses MarkupSafe. These are existing host build tools, not new
EmberBSD Python helpers. Set `PYTHON_EXECUTABLE` to the common image interpreter.
The helper uses their upstream CLI and records the installed image package
versions when `pkg_info` is available. It does not install another interpreter,
run pip, or provide the Python `volk_modtool` utility. Neither the library nor the
installed C++ consumer requires Python at runtime.

The shell, CMake and C/C++ contract files are original AI-assisted EmberBSD work
under the MIT license. The deterministic numerical fixtures and scalar expected
values are original. No upstream test or example implementation is copied.
Upstream license texts are retained under `install/share/ember-volk/licenses`.
