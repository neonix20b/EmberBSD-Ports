# EmberBSD sysroot provenance

The target system is EmberBSD. Its retained NetBSD ABI, compiler triplets,
ELF notes and pkgsrc platform variables are compatibility interfaces. They
do not select upstream NetBSD kernel, libc, headers or drivers as substitutes
for the fork. Preserve upstream copyright and source identifiers.

## Preparing and updating a sysroot

Use a destination tree built from a pinned EmberBSD commit and configuration.
Keep its base-library, header, startup-object and toolchain provenance together:
source revision, compiler and build configuration, artifact hashes, and the
target acceptance performed. Target pkgsrc metadata covers packages under
`/usr/pkg`; it does not establish the origin of base `/lib`, `/usr/lib` or
`/usr/include`.

Do not complete a partially populated sysroot by extracting whichever files
are missing from upstream `base` or `comp` sets. Different paths can resolve
to distinct libc copies. A complete fork build is the preferred replacement;
a component-only repair must identify every replaced alias, preserve rollback
outside the sysroot, and state which other components remain unverified.
Old recovery libraries must not remain reachable through compiler or loader
search paths. A profiled libc archive cannot be replaced with an unprofiled one.

The common cross profile compares `/lib/libc.so`, `/lib/libc.so.12`,
`/usr/lib/libc.so` and `/usr/lib/libc.so.12` before extraction. Missing or
different bytes stop that package build. This consistency check cannot tell
whether four identical copies are from EmberBSD; the source receipt and
regression tests remain necessary. Reassess already-built consumers after
changing any selected provider. A successful package build does not certify
an entire base release.

## Verified libc repair, 2026-10-09

A graphics cross sysroot contained the accepted fork's shared libc in
`/usr/lib`, an old upstream copy in `/lib`, and an old static archive.
The cause was a local helper that filled missing paths from upstream sets.
That helper was retired. All shared aliases now resolve to one accepted fork
artifact; the static archive matches its original accepted build. The old
profiled archive was quarantined outside the sysroot pending a proper rebuild.

The artifacts come from EmberBSD commit
`cffffd40b995ee0c1ada70d6f4c156409b22bae5`, built with GCC 12.5 on Zero 3W.
They are not a new GCC16 build of libc. The OS owns their
[source repair and original acceptance](https://github.com/oxtech-ember/EmberBSD/blob/main/ember/boot/aarch64-outlined-cas.md).

| Artifact | SHA256 |
| --- | --- |
| Shared libc | `5dff821f1a1b42845e642cedd16375b310b78d04fa624bb21472d33b0fc14130` |
| Static libc | `be6a1144daa7d63c9c22dbd6c4bbe647d7d8dcc69a17deebe4d63395f4375cf6` |

The existing OS CAS regression was freshly cross-compiled with GCC 16.2.
The same objects were statically linked once to the repaired archive and once
to the old archive. On EmberBSD/CM5, the repaired executable passed all 850
checks across 20 variants; the old archive produced 140 failures. Link maps
identify the selected archives. Temporary execution preserved source hashes
and removed its remote files. No base installation or reboot was performed.

This establishes the repaired static provider and consistent shared aliases.
Eight sampled base headers matched the inspected fork, but the entire header
tree and base userland have not been rebuilt and accepted together. A complete
current EmberBSD sysroot/base release remains outstanding; these bounded
results must not be described as that release or as GPU/NPU acceleration.
