# Source and patch provenance

- The selected UTM dependency is virglrenderer 1.3.0 at
  `5d26f605f50f8e22002ec6db5fb775e1992d4e96`, pinned by the official
  [UTM v5.0.6 source selection](https://github.com/utmapp/UTM/blob/v5.0.6/patches/sources).
  It is an experimental beta dependency candidate, not an installed host.
- The original GitHub API archive and accepted upstream patch are pinned in
  [`sources.tsv`](sources.tsv), with the original upstream reference archive.
  Original input bytes were SHA256-verified on 2026-10-07. The reference
  archive is provenance for inspection; preparation requires only the UTM
  archive and the original patch carried here.
- Upstream author: Yiwei Zhang `<zzyiwei@chromium.org>`; authored
  2026-09-27; accepted 2026-10-05 by Marge Bot. Title:
  `vrend: prevent size truncation in check_iov_bounds`.
  [MR 1686](https://gitlab.freedesktop.org/virgl/virglrenderer/-/merge_requests/1686)
  and [commit 123e0bc](https://gitlab.freedesktop.org/virgl/virglrenderer/-/commit/123e0bc30504c7e745fc008debce30ab0d9a2955).
- [`patches/123e0bc-upstream.patch`](patches/123e0bc-upstream.patch) is the
  original mail patch, including the upstream author and identifier.
  SHA256: `a1c804a65190f5d11caa150748e80655f9f98617a7b5711e1529d522cd32e68e`.
- `prepare.sh` changes only `virgl_get_iovec_size` to the existing fork name
  `vrend_get_iovec_size`, and hunk start lines 9167/9190 to 9376/9399.
  There is no locally substituted fix, prerequisites or change of semantics.
  Derived patch SHA256:
  `8ea940b70f7ee4563ed4dc36e5d835a3ec9347fdcf65523bb9e891659906b1d7`.
  Complete patched `src/vrend/vrend_renderer.c` SHA256:
  `34d99a5726459112444cab327e1ed7849fc732e7e3a5704dbfa641dc05747c87`.
- The fork's IOV sum already returns `size_t`; its transfer-size helper
  already returns `uint64_t`. The fork and selected upstream `u_format.h`
  are byte-identical. `util_format_get_2d_size` takes `size_t stride` and
  multiplies in `size_t`, so the widened minimum/default-layer locals work
  without another patch. The row helper's unsigned product remains unfixed.
- The original renderer and format-generator/table notices are preserved
  in extracted/generated private sources. The renderer is MIT, derived
  partly from Mesa; [`LICENSE.upstream`](LICENSE.upstream) retains its
  root license. `iov.c` retains Michael Ringgaard's original 2002 BSD
  three-clause notice. Tests compile that original file, without redistributing
  its implementation here. New shell/AWK/C material is BSD-2-Clause under
  [`LICENSE.tests`](LICENSE.tests), AI-assisted by Codex.

Archives, extracted sources, generated format tables, binaries and complete
logs belong in a private work directory. They are excluded from this probe's
tracked export. The [README](README.md) states the causal checks and limitations.

## Local reported CREATE failure stage

[`create-sources.tsv`](create-sources.tsv) pins five original raw QEMU files at
`6601422e1fff2da1376faafb1e4c2c5cdb2d8003` and the complete UTM overlay at
`968fef31ee3299224feaf4de1e40e1e5f46369c1`. Their URLs and SHA256 were verified
on 2026-10-07. Full original Red Hat/Airlie/Hoffmann GPL-2.0-or-later notices
remain in the private QEMU inputs and extracted function compilation. The
original QEMU [COPYING](https://github.com/utmapp/qemu/blob/6601422e1fff2da1376faafb1e4c2c5cdb2d8003/COPYING)
is the license referenced by those notices. These raw files are not a complete
QEMU checkout. The original UTM overlay remains unchanged, with its authors
and mail headers; sequential hunk-range checks establish that neither CREATE
function is modified. Complete overlay application/build is unverified.

Local patches are authored by EmberBSD contributors with Codex AI assistance:

- [`create-qemu-local.patch`](patches/create-qemu-local.patch): report short
  CREATE/wrapper OOM and reject nonzero renderer status before publication.
  SHA256 `a1a8bc72138759435fe4f99f96463bf1cf229a0e3f54edbde64767e4037bdcd7`.
- [`create-renderer-local.patch`](patches/create-renderer-local.patch): use
  the existing renderer destructor on reported allocator error, after the
  unchanged accepted IOV backport.
  SHA256 `3f131d11dd3d5e570c5f57df4d3bb4611e053b2a5cea75ea06e9f6c908e93ef1`.

Neither local patch is submitted or accepted upstream. Original renderer
MIT notices and Chromium resource-table authorship are preserved. New tests,
shell and AWK are BSD-2-Clause under `LICENSE.tests`. The complete CREATE-stage
QEMU file SHA256 is
`4eb8fc1fc00dc8a159de537a4c9d11e6cc4f2b9c444f7cf4bf235d06b0a3f330`;
the IOV-plus-CREATE renderer file SHA256 is
`7bb55e69e483df96d7e14895dab2e0cae6f13d60c8fcd0293169a2942fe421df`.
[`CREATE.md`](CREATE.md) records preparation, causal checks and limitations.

## Classic backing ownership stage

[BACKING.md](BACKING.md) describes the local AI-assisted foundation. Its only
production target is QEMU `hw/display/virtio-gpu-virgl.c`; the patch is local,
not submitted or accepted upstream. Red Hat authors and GPL-2.0-or-later notices
remain in all prepared QEMU files. Renderer code is unchanged beyond the prior
accepted IOV/local CREATE stages. Selected renderer originals come from the
same archive and retain MIT/BSD notices, including Michael Ringgaard's IOV code.
New shell/AWK/C helpers retain `LICENSE.tests` and SPDX BSD-2-Clause notices.

`prepare-backing.sh` consumes the complete pinned mbox and records all sections,
including exclusions. It preserves author/subject/commit metadata in each of
eight selected complete file diffs. No individual function hunks are selected
from that overlay. C8b QEMU hunk coordinates are derived mechanically with
complete exact-context and complete CREATE-body identity checks; the accepted
raw patch/entry bytes remain unchanged. Preparation records complete source
SHA256 receipts. No full host build or upstream acceptance is implied.

| Prepared source or patch | SHA256 |
|---|---|
| Post-overlay GPU GL | `36ae5b2763e48aa696a574ac7c50c46e59020cfa47989d1c2d0deb000ad174f4` |
| Post-overlay GPU VirGL | `fa586e30890ca8e55899b69151bcba043acb89b1deddd2b89f8c27d4fb81c1e0` |
| Post-overlay GPU | `669effd30d221024f40af56b842247a5a2be8c68bc471ac533415214ac48d304` |
| Post-overlay GPU header | `25e032f22e32d860fea74c1e598de1df0268111a1d2e7367dcbdd9e5f42a8a73` |
| Post-overlay plus C8b GPU VirGL baseline | `c381fd9bdf0c6fb3e58dcb01c263b1cc77d510f0b39fa31e654933c7de1f5544` |
| Final GPU VirGL ledger | `a7bb36d50c0ff30a88a2313554fbf3c73a3f9bf24298a10035ac6351ecf26e5f` |
| `patches/backing-qemu-local.patch` | `d5e6a264f3902843f0225723aaa6cdface622bdd1c5516338a08a38e2c2d72de` |

## Reported completion status stage

[COMPLETION.md](COMPLETION.md) describes the local AI-assisted QEMU-only delta
in `patches/completion-qemu-local.patch`. It is not submitted or accepted
upstream. The complete accepted lifecycle outputs remain separate inputs;
`completion-sources.tsv` pins their hashes, the delta and complete resulting
GPU VirGL source. All original source and overlay authorship remains intact.
The renderer is unchanged by this stage. New shell/Ruby/C helpers use
BSD-2-Clause under `LICENSE.tests`; source-derived bodies retain their original
licenses and are extracted into private test work only. Full host builds,
native graphics behavior and an installed accelerated session are unverified.
