# GDB 18.1 package

The development profile replaces `devel/gdb` with the current
[canonical recipe](../recipes/devel/gdb). Sources still come from the
upstream release server; the recipe verifies archive and patch checksums.
The export dereferences links to the shared Ports patches and helper.
It does not retain an older GDB recipe alongside this one.

## Build

Prepare a new pkgsrc tree using the development-toolchain or common-build-tools
profile, following the [profile instructions](../README.md). For macOS cross
builds, use the [common package cross environment](../../common-build-tools/cross/README.md)
with the accepted GCC16 compiler, complete NetBSD 11/AArch64 sysroot and
matching installed target dependencies.

```sh
sh scripts/prepare-pkgsrc.sh /absolute/new-pkgsrc common-build-tools
bmake -C /absolute/new-pkgsrc/devel/gdb \
    MAKECONF=/absolute/cross-mk.conf BATCH=yes package
```

The native target is NetBSD/AArch64. The package uses shared GCC16, GMP,
MPFR, Readline, Expat, zlib, liblzma, curses and zstd. Its `gstack` script
uses `/bin/sh`; Bash is not an additional runtime dependency. Python/Guile
scripting, debuginfod, Intel PT, Babeltrace, gdbserver and the simulator are
disabled. Package creation retains pkgsrc's file, interpreter, RPATH and
dependency checks.

The package includes the native backend, supplementary bounds and iconv
repairs described in [README.md](README.md), plus the
[expression and location-list repairs](dwarf-variants.md). The installed
ELF's runtime paths are `/usr/pkg/gcc16/lib:/usr/pkg/lib`.

## Install and accept

Keep a rollback copy of an existing standalone debugger outside PATH.
Install the archive and its complete dependency closure through `pkg_add`:

```sh
PKG_PATH=/absolute/packages pkg_add -U /absolute/packages/gdb-18.1.tgz
pkg_admin check gdb-18.1
/usr/pkg/bin/gdb -nx -nh -batch -ex 'show version'
```

Use the matching source revision to build the external-DWARF and live ABI
fixtures in [README.md](README.md), then run `test-target.sh` against the
installed executable. Run the expanded [DWARF matrix](dwarf-variants.md)
separately, including the agent-expression recursion checks. Record real
failures and unsupported cases; a valid expression rejected by the debugger
does not become conforming merely because its rejection is reproducible.

The OS repository owns the
[offline development-image builder](https://github.com/oxtech-ember/EmberBSD/tree/main/ember/image).
It selects `/usr/pkg/bin/gdb` through `/usr/bin/gdb`, removes the old base
`gdbtui` entry point, and installs a pinned, fully checksummed local package
closure on first boot. Ports owns the debugger package and acceptance;
the OS owns image assembly, boot and filesystem recovery.

Package checks alone do not establish a bootable image. Image acceptance
must finish first-boot installation, confirm package integrity and exercise
the installed debugger after a normal reboot. Neither this package nor the
bounded DWARF matrix establishes universal DWARF conformance.

## Accepted package and image

On 2026-10-08 the macOS cross-built package passed the normal pkgsrc checks,
native installation and all 42 registered file checks in NetBSD 11/AArch64.
The installed debugger passed the external-DWARF and live ABI suite, the
[expanded matrix](dwarf-variants.md), and `gstack` attachment to a live process.
The expression runner retains two known `DW_OP_entry_value` failures.

The archive SHA256 is
`a04fabdc497b7cc1f7a4c653d5834f545a47a36b92d17fede505fc9e8ef5419c`;
the installed ELF SHA256 is
`eb1c0bb10217764350b530fdf089b288f18a3ad913e0fa14da517645d9b55356`.
The OS-owned image passed offline installation of all eleven closure packages,
integrity checks, live DWARF5 split-DWARF32/64 debugging and a normal reboot in
QEMU/HVF. The linked image guide records its inputs, image hash and limits.
