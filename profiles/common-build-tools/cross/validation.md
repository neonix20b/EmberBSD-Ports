# Cross package validation

The package workflow below was checked on 2026-10-08. Ports owns the recipes,
patches and acceptance scripts. The macOS build host used the Ports GCC
16.2.0 cross compiler and the pinned common-profile pkgsrc export. The target
was an AArch64 UTM guest with EmberBSD `EMBER64`, a NetBSD 11.0 base and the
complete `gcc16-16.2.0nb1` package. No desktop was required.

This is VM execution evidence for the named packages. The guest kernel used
bootstrap GCC12.5; these results do not claim a GCC16-built OS, acceptance of
LLVM23/Python314 packages or execution of these new packages on a board.

| Package | Checks completed |
| --- | --- |
| pkgconf 3.0.7 | Mac cross build and pkgsrc package checks; normal target installation; all 15 upstream API groups and 14 CLI groups; an installed C library consumer. |
| GNU M4 1.4.21 | Mac cross build and pkgsrc package checks; target installation and Info registration; 242 upstream manual examples with seven unsupported `changeword` cases skipped; stack-overflow check passed. |
| Libtool 2.6.2 | Verified original source, maintained/generated patch equivalence; cross package checks and installation; C11/C++20 shared/static consumers, exceptions through a DSO, selected GCC16 runtime, libtoolize, shlibtool and uninstall. |

Package SHA256 values identify the actual VM inputs:

```text
pkgconf-3.0.7.tgz     351af223d73169baba9a277208e8d7a6e7682984f5151c32ee7f18432bdfd221
m4-1.4.21.tgz        026972df19145afe7806e6d0eec3450edfd0d542b26789e3652a34491a9c198c
libtool-base-2.6.2.tgz 0862a6c6ab789dd880c017da93ac72fe1f0cb59e19460c9f0b6fb9148a8776e6
```

The original-source hashes and URLs are in [sources.tsv](../sources.tsv).
The test entry points and prerequisites are described in [README.md](README.md).
Normal pkgsrc file, interpreter, permission, PIE/RELRO, RPATH and work-directory
checks remained enabled. Installed package integrity was checked on the guest.

The cross regression uses actual pkgsrc parsing and package metadata. It
covers native host dependency selection, missing inspection tools and target
libraries, malformed ELF, script/empty-file handling, target symlink aliases,
cycles, package-owned libraries and explicit shared-library exceptions.
The constrained Info-tool case also rejects a missing target utility and
unrelated unsupported runtime tools.

A separate package-manager regression compares the original and repaired
`pkg_add` using isolated package databases. It exercises alternate-root
installation/update and same-version reinstall, target ownership paths,
script suppression, preservation of another package's parent directory,
partial-extraction rollback and unchanged native replacement behavior. These are
host-side package-manager checks, not execution of target binaries.
