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
