# GCC 16 C++ modules allocation on NetBSD

The GCC 16.2.0 candidate can crash while writing a C++ module CMI on a
filesystem that rejects `posix_fallocate`. NetBSD returns `EOPNOTSUPP` (45),
while its `ENOTSUP` is 86. GCC's original `elf_out::create_mapping` falls back
to `ftruncate` only for `EINVAL`; its upstream `ENOTSUP` repair alone does
not cover the observed NetBSD return value.

`patches/gcc-modules-fallocate.patch` packages Rainer Orth's accepted GCC
commit `a94156b8ee7165c32f73f9cd11c9b8f3b8687d3b` (2026-05-05) and adds an
AI-assisted local `EOPNOTSUPP` extension. The original patch URL/SHA256 is
pinned in `sources.tsv`. The extension has not been submitted or accepted
upstream. GCC's GPLv3+ license, authorship and identifiers remain intact.
The allocation fallback still rejects other errors, including `ENOSPC`,
`EACCES`, `EBADF` and `EIO`, and preserves failures returned by `ftruncate`.

The compiler source changes, so the exported package is
`gcc16-16.2.0nb1`. Its companion recipe is `gcc16-libs-16.2.0nb2`, preserving
pkgsrc's required higher libs revision. The repair does not change runtime
library code or require installing a second runtime provider. The separate
`gcc16-libjit` recipe retains its revision because this C++ frontend change
does not alter libgccjit.

## Source regression

Download the original pinned GCC archive and upstream patch, then run:

```sh
sh profiles/development-toolchain/tests/modules-fallocate.sh \
    /absolute/gcc-16.2.0.tar.xz /absolute/upstream.patch /absolute/new-output
sh profiles/development-toolchain/tests/source-profile.sh
```

The regression verifies both downloaded hashes, applies the actual exported
pkgsrc patch to the actual GCC source, checks pkgsrc's patch checksum, and
extracts the allocation lambda from baseline, upstream-only and final sources.
It compiles the extracted lambda with controlled allocation/truncation calls
and explicitly distinct NetBSD error constants. Baseline and upstream-only
must reject 45; the final branch must pass unsupported-operation cases while
rejecting unrelated allocation errors. Stale `errno`, offset/length arguments,
failed truncation and the `HAVE_POSIX_FALLOCATE`-absent branch are covered.
Duplicate/missing extraction shapes, corrupt checksums and repeated patch
application are rejected. These are production-function source contracts;
they do not establish a rebuilt native frontend or installable package.

## Native acceptance boundary

Use the committed source delta with the retained configured native GCC build.
Preserve the original source, `cp/module.o`, `cc1plus`, command lines and hashes
before replacing owned outputs. Recompile only `cp/module.o` and relink
`cc1plus`; do not rebuild unchanged GCC objects or modify original suite logs.
Test with the existing installed GCC driver and a private `-B` frontend prefix,
starting with the unchanged upstream `atom-pragma-1.C`, then export/import/link
and run a small module consumer. Keep the ordinary loader and existing runtime.

A private frontend proof and pkgsrc staging/package validation are separate
levels. Keep the original package for rollback. Do not infer that this repair
resolves all failures in the original full module suite. Common consumer
selection must require the repaired package revision while retaining the valid
`GCC_REQD=16.2` major/minor floor; that policy update needs its own real pkgsrc
metadata validation. Native compiler, package and policy results are pending.
