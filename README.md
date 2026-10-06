# EmberBSD Ports

Source build recipes, portability patches and build probes for
[EmberBSD](https://github.com/apovalixin/EmberBSD).

Sources are downloaded from their original upstream locations and verified
against pinned hashes. This repository carries our recipes and patches,
with their provenance and validation limits. It does not mirror source
archives or store generated binaries.

## Current contents

- [Phosh native build probe](probes/phosh/README.md): GNOME Bluetooth and
  gmobile libraries build; Phosh 0.58.0 configuration is blocked by missing
  GTK3 Wayland and further system integration dependencies.

The initial entry is an experimental probe, not an installable Phosh
package or a working mobile session. Its helper stops on errors and keeps
build output in a private user directory.

## Package integration

The preferred foundation for package recipes is
[pkgsrc](https://www.netbsd.org/docs/pkgsrc/components.html), already used
by EmberBSD's NetBSD-derived package environment. It provides upstream
fetching, checksums, patches, dependency handling and binary packaging.
This repository does not implement another package manager.

Future installable recipes should use pkgsrc's `Makefile`, `distinfo`,
`DESCR`, `PLIST` and `patches/` conventions. Experimental probes remain
under `probes/` until their package integration and runtime are validated.
No pkgsrc overlay or binary package repository is provided yet.

## Contributions and provenance

All repository material is written in English. Record the upstream
version, URL, archive hashes, license and origin of each patch. Preserve
upstream copyright and SPDX notices. State whether patches are local,
submitted upstream or accepted upstream; AI assistance is not concealed.

Distinguish a configured project, a compiled library, passing tests and
a working application. Keep logs and downloaded artifacts outside Git.
Examples that use these ports belong in
[EmberBSD Examples](https://github.com/neonix20b/EmberBSD-Examples).
