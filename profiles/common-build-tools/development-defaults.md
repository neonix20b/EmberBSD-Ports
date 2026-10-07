# Reversible native development defaults

This procedure selects the installed repaired GCC16 for new development sessions
and ordinary pkgsrc consumers on NetBSD 11/AArch64. It does not replace base
compiler files, migrate existing C++ packages or accept a release image.
The [native validation](../development-toolchain/native-validation.md) records
its physical Zero 3W A733 acceptance and remaining compiler limits.

## Prerequisites and rollback

Prepare a committed common-tools export and install `gcc16-16.2.0nb1` or newer
with normal `pkg_add -u`. Preserve the original compiler package and verify
both package hashes before installation. Record `pkg_info` identity/dependencies,
`pkg_admin check gcc16`, installed frontend hash and base compiler hashes.
Do not rebuild GCC through the common default during this update.

Back up `/etc/login.conf`, its optional `.db`, `/etc/mk.conf`, the affected
user's `.profile` and any existing durable common profile. Preserve ownership,
permissions and hashes; record absence instead of inventing an original file.
Keep the current administrative connection open for rollback. Install staged
configuration files atomically. Retain the backup until new independent SSH
and login-shell checks pass. If they fail, restore the saved files and remove
only files recorded as originally absent; check a fresh connection again.
Package rollback uses `pkg_add -u ORIGINAL_GCC16_PACKAGE`, after restoring the
previous selection. Never overwrite `/usr/bin/cc` or the base runtime.

## Durable pkgsrc policy

Copy the committed `profiles/common-build-tools/mk.conf` to
`/usr/pkg/etc/emberbsd/common-build-tools.mk.conf`, mode 0644, root ownership.
Verify its hash against the committed source and the exported
`EMBERBSD-COMMON-TOOLS-MK.CONF`; never include a temporary export from the
system default. Small later metadata/recipe changes should use a bounded,
verified update of an owned export where exporter/patch contracts permit.
Record source and resulting file identities. Full unchanged pkgsrc extraction
was the dominant delay on the checked SD storage. On a host with no previous
`/etc/mk.conf`, install:

```make
.if defined(BSD_PKG_MK)
PREFIX= /usr/pkg
LOCALBASE= /usr/pkg
.include "/usr/pkg/etc/emberbsd/common-build-tools.mk.conf"
.endif
```

For an existing configuration, preserve unrelated settings and integrate these
lines before the common include. PREFIX and LOCALBASE must be defined when
the profile evaluates them. The profile requires full `gcc16>=16.2.0nb1`,
`GCC_REQD+=16.2`, `USE_PKGSRC_GCC_RUNTIME=no` and one worker. It also declares
current Python/Meson/LLVM policy; declaring it does not install those packages.

Native-GCC bootstrap and its prerequisite closure use a separate private
MAKECONF with the development profile and explicit base compiler selection:

```make
.if defined(BSD_PKG_MK)
PREFIX= /usr/pkg
LOCALBASE= /usr/pkg
PKGSRC_COMPILER= gcc
USE_NATIVE_GCC= yes
USE_PKGSRC_GCC= no
CC= /usr/bin/cc
CXX= /usr/bin/c++
.include "/absolute/bootstrap-pkgsrc/EMBERBSD-DEVELOPMENT-MK.CONF"
.endif
```

Run the bootstrap build with an explicit base PATH:

```sh
env PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/pkg/sbin:/usr/pkg/bin \
    make MAKECONF=/absolute/bootstrap.mk.conf package
```

Include no common-tools policy there. Explicit MAKECONF replaces the system
config. This exception keeps base bootstrap independent of GCC16;
it is not an alternate application toolchain. Fresh CMake/Meson build trees
should also select the installed compiler explicitly; existing caches retain
the compiler they originally selected.

## New session PATH

The GCC package already installs `cc`, `c++`, `cpp`, `gcc` and `g++` in
`/usr/pkg/gcc16/bin`. Prefix this directory to every preserved normal path.
[NetBSD login.conf](https://man.netbsd.org/NetBSD-11.0/login.conf.5) uses a
space-separated path capability. When there is no active default class, add:

```text
default:\
    :path=/usr/pkg/gcc16/bin /sbin /usr/sbin /bin /usr/bin /usr/pkg/sbin /usr/pkg/bin /usr/games /usr/X11R7/bin /usr/local/sbin /usr/local/bin:
```

An existing default class must retain its other capabilities. A nondefault
user class requires its own corresponding path policy. If using `cap_mkdb`,
create the database from the staged file and atomically install the text and
matching database. Change no authentication capability or SSH service setting.

A user `.profile` can reset PATH after the login class. Prefix the package
directory in that existing assignment too, preserving other paths and any
rescue-path exception. On the checked root `/bin/sh` profile, the initial
assignment becomes:

```sh
export PATH=/usr/pkg/gcc16/bin:/sbin:/usr/sbin:/bin:/usr/bin:/usr/pkg/sbin:/usr/pkg/bin
```

Keep its later PATH additions. A fresh nonlogin SSH command verifies the actual
sshd class setup; a fresh login shell verifies profile handling. No reboot or
sshd restart is required. Current processes and existing GUI packages retain
their previous runtime closure.

## Focused acceptance

In each fresh connection, record PATH, `command -v` and `-dumpfullversion` for
`cc`, `c++`, `gcc` and `g++`. All must resolve under `/usr/pkg/gcc16/bin` and
report 16.2.0. Check explicit `/usr/bin/cc` still reports the base compiler and
matches its original hash. Verify real pkgsrc metadata through `/etc/mk.conf`
requires the complete repaired package without `gcc16-libs`; verify the private
bootstrap MAKECONF still selects `/usr/bin/cc` independently.

Run the existing [native selection fixture](tests/native-compiler-selection/README.md)
once with the actual exported sources and `/etc/mk.conf`. It supplies no
PREFIX/LOCALBASE override, so the configuration itself must establish them.
It packages, installs, runs and inspects a C/C++20 consumer through the actual
pkgsrc wrappers, checks loaded GCC16 libraries with GDB, and removes its package.
Run the unchanged upstream atom reproducer and module export/import/link/run
through [modules-native.sh](../development-toolchain/tests/modules-native.sh)
with the `installed` selector. This mode obtains the frontend from the installed
driver and supplies no private `-B` override:

```sh
sh profiles/development-toolchain/tests/modules-native.sh \
    ORIGINAL_ATOM_PRAGMA /usr/pkg/gcc16/bin/g++ installed NEW_OUTPUT
```

Use the normal bounded device resource supervisor and one compiler worker.
No loader override, full GCC rebuild or upstream-suite rerun is needed for
this scoped installed-package/default gate. Complete module support,
self-hosting, current binutils, common Qt/LLVM rebuilding and fresh-image
acceptance remain independent requirements.
