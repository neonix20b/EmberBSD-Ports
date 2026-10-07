# Cross-building common packages on macOS

This opt-in path builds ordinary NetBSD 11/AArch64 pkgsrc packages with the
[GCC 16.2 cross compiler](../../development-toolchain/cross/README.md).
The compiler and build tools execute on macOS; installed packages are tested
on EmberBSD. This does not yet establish a complete GCC16-built OS or accept
Python, Meson or LLVM target packages.

Use the `common-build-tools` export from the parent profile. It preserves the
pinned pkgsrc revision and obtains original upstream archives with recipe
checksums. The cross fixes also compose into profiles based on common tools.

## Prerequisites

Prepare these separate directories, outside Git:

- A working GCC16 cross prefix targeting `aarch64--netbsd`.
- NetBSD host tools built on the Mac, including `aarch64--netbsd-install`.
- A pkgsrc unprivileged macOS bootstrap with BSD make, the patched package tools,
  mksh and digest. Use the exported `pkg_install-20260227nb1` recipe: it fixes
  alternate-root replacement and suppresses target deinstall scripts during
  cross updates. Its package database describes host executables only.
- A target sysroot with headers, complete base libraries and development
  files (including `libintl`), the complete accepted
  `gcc16-16.2.0nb1` package, its dependency files and target package database.
  Include base `/usr/bin/install-info` for packages shipping Info manuals.

Do not substitute a host package database for the target database. The
selected target GCC runtime needs its CRT files and `libstdc++.so.7`; a
compiler executable alone does not satisfy these prerequisites. This profile
rejects building `lang/gcc16` as a consumer: its Canadian-cross package recipe
is a separate, unfinished step.

Compose the existing tools without rebuilding them:

```sh
sh profiles/common-build-tools/cross/prepare-tools.sh \
    /absolute/gcc16-prefix /absolute/netbsd-tools /absolute/new-cross-tools
```

A private MAKECONF includes the host bootstrap configuration first:

```make
.include "/absolute/host/etc/mk.conf"
.if defined(BSD_PKG_MK)
EMBERBSD_CROSS_TOOLS=/absolute/new-cross-tools
EMBERBSD_CROSS_SYSROOT=/absolute/target-sysroot
EMBERBSD_CROSS_HOST_PREFIX=/absolute/host
WRKOBJDIR=/absolute/work
DISTDIR=/absolute/distfiles
MAKE_JOBS=4
# Optional when these host tools are already installed:
TOOLS_PLATFORM.makeinfo=/absolute/host-texinfo/bin/makeinfo
TOOLS_PLATFORM.msgfmt=/absolute/host-gettext/bin/msgfmt
.include "/absolute/EmberBSD-Ports/profiles/common-build-tools/cross/mk.conf"
.endif
```

Use the host BSD make to build a target package, for example:

```sh
/absolute/host/bin/bmake -C /absolute/export/devel/pkgconf \
    MAKECONF=/absolute/cross.mk.conf package
```

Pkgsrc resolves native build dependencies separately from target runtime
packages. Add private paths for any required host tools through pkgsrc's tool
configuration. The NetBSD target remains `/usr/pkg`. Cross `install` populates
the private sysroot with package scripts disabled; actual `pkg_add` on the
target runs installation scripts, including Info registration.

Build-time C/C++ generators use `/usr/bin/cc` and `/usr/bin/c++` on macOS.
Override `EMBERBSD_CROSS_BUILD_CC` and `EMBERBSD_CROSS_BUILD_CXX` with absolute
host compiler paths when necessary. They reach upstream configure as
`CC_FOR_BUILD` and `CXX_FOR_BUILD`; target wrappers still compile the package.
Host tool dependencies read the host bootstrap MAKECONF, so interpreter and
tool choices needed by those dependencies belong there as well.

## What the cross adaptation checks

Host dependency recursion drops cached target platform values. Target package
metadata uses cross `readelf` and sysroot libraries, never the macOS loader.
It rejects missing ELF files, failed inspection tools and unresolved DSOs.
Scripts and empty files are not ELF providers. Relative, absolute and directory
symlink aliases resolve inside the target staging tree and sysroot; loops fail. Existing package-owned DSO
filtering and `CHECK_SHLIBS_SKIP` shell patterns remain supported.

Compiler wrappers preserve the selected GCC16 CRT and runtime paths even
when Libtool reconstructs its link command. Packages retain normal pkgsrc
file, permission, RPATH and shared-library checks, and record root/wheel
ownership rather than the Mac user's UID.

The only cross runtime-tool exception is NetBSD base `install-info`, verified
in the sysroot. Its build wrapper is a no-op and the installation script names
`/usr/bin/install-info` on the target. Other unsupported `:run` tools still
fail explicitly. Libtool declares GNU M4 as a target package dependency.

## Acceptance

Run `tests/cross-pkgsrc.sh` against a staged pkgconf package. It exercises real
pkgsrc parsing, native dependency recursion, ELF metadata and failure cases.
`tests/cross-tools.sh` checks tool composition, refusal of existing output,
missing host tools and the constrained target Info utility selection.
`tests/cross-generators.sh` checks native/cross Libtool auxiliary selection
and executes C/C++ generators through the real configure environment. It
also rejects missing compiler exports and invalid compiler paths.
The separate `tests/pkg-add-sysroot.sh` compares original and repaired host
package tools. It checks replacement, same-version reinstall, shared-directory
ownership, partial-extraction rollback and native behavior.
These scripts print their required positional arguments when called without
arguments. Set `BMAKE` to the host bootstrap BSD make.

Target acceptance scripts in this directory require a new output directory:

- `run-pkgconf-tests.sh`: upstream API binaries and CLI fixtures, plus an
  installed C API consumer built with the selected GCC16.
- `run-m4-tests.sh`: upstream manual examples, stack-overflow test and Info
  registration through the installed package.
- `run-libtool-tests.sh`: C11/C++20 shared and static consumers, exceptions,
  actual runtime linkage, libtoolize, shlibtool and uninstall.
- `run-binutils-tests.sh`: GNU assembler/linker and archive consumers,
  DWARF5/64, split debug information, stripping, C++ DSO exceptions,
  GNU CTF and unresolved-symbol errors; see [Binutils](../binutils.md).

Pkgconf builds its test binaries as upstream `noinst_PROGRAMS` during `all`.
Copy the actual `WRKSRC/.libs/test-api-*` and `.libs/test-runner` ELF files;
the similarly named files in WRKSRC itself are host Libtool shell wrappers.
Copy pristine upstream `tests/` and `t/` directories separately from those
cross-built binaries. For GNU M4, transfer upstream `checks/` and `examples/`.
On macOS, create transfer archives with
`COPYFILE_DISABLE=1 tar --no-xattrs --exclude '._*' ...`; AppleDouble files
otherwise become unintended test inputs on NetBSD. Do not count a host
execution or version string as target acceptance. The [Libtool record](../libtool.md)
explains source regeneration and target script conversion.
