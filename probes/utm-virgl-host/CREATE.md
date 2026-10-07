# Reported CREATE failure publication and unwind

This experimental source stage helps prevent a rejected VirGL CREATE from
leaving a falsely published QEMU resource. EmberBSD Ports owns the local
AI-assisted patches. It is a focused host software contract, without a complete
QEMU build, installed host or acceleration qualification.

The selected target remains UTM v5.0.6 Beta
`968fef31ee3299224feaf4de1e40e1e5f46369c1`, QEMU
`6601422e1fff2da1376faafb1e4c2c5cdb2d8003`, and renderer 1.3.0 fork
`5d26f605f50f8e22002ec6db5fb775e1992d4e96`. The original renderer archive and
accepted Yiwei Zhang IOV backport retain their existing `sources.tsv`,
`prepare.sh`, hash and test contracts. The installed recovery host is unchanged.

## Source preparation

Supply the original renderer archive and a directory containing all six
exactly named raw inputs in [create-sources.tsv](create-sources.tsv):

```sh
sh prepare-create.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-source-work
sh test-create.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-test-work
sh tests/guards-create.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-guard-work
```

No script downloads, installs or enables anything. Inputs must be downloaded
from the manifest's original URLs. SHA256 validation precedes extraction or
patching. Work directories must be new and absolute. The existing IOV preparer
runs unchanged; the CREATE renderer patch applies to a separate copy of its
patched tree. The raw QEMU inputs retain full notices. Local patch application
uses zero fuzz, rejects offsets and requires exact final file hashes.

The complete pinned UTM overlay is preserved, not applied to an incomplete
QEMU tree. An AWK audit checks every hunk in its three sequential VirGL file
diffs against the exact original CREATE ranges. It adjusts those ranges for
preceding changes between patches and rejects any overlap. This proves the
selected CREATE functions are untouched by that pinned overlay. It does not
verify the overlay's full-tree contexts or offsets. Full QEMU integration needs
its complete source tree, generated headers, dependencies and UTM build settings.

[PROVENANCE.md](PROVENANCE.md) records patch status, authorship, licenses and
output hashes. Local patches have not been submitted or accepted upstream.

## Behavior

Both QEMU CREATE handlers set INVALID_PARAMETER before their existing checked
fill macro and clear it only after a complete body is read. This covers a short
CREATE body after a complete header. Zero and duplicate IDs retain their local
INVALID_RESOURCE_ID behavior, before allocation.

The unpublished wrapper uses `g_try_new0`. Failure returns OUT_OF_MEMORY without
calling the renderer. Initialization and all forwarded creation fields remain
unchanged. Renderer creation precedes one reslist insertion. Any nonzero return
frees only the unpublished QEMU wrapper. Positive and negative ENOMEM map to
OUT_OF_MEMORY; other values, including INT_MIN, map to UNSPEC without negation.
There is no compensating renderer unref after unsuccessful creation.

On a reported renderer allocator failure, the existing actual destructor
releases the acquired resource. It uses existing storage flags and owned handles.
External `image_oes` remains caller-owned. Texture failure paths clear their GL
binding before the creator invokes destruction. The existing from-pipe wrapper
failure unref remains unchanged and occurs exactly once. Successful resources
retain ordinary UNREF and fence completion routing.

## Focused verification

On 2026-10-07, Apple Clang 21.0.0 on macOS/arm64 compiled actual original and
patched functions with C11, `-Wall -Wextra -Werror`. Unused seam hooks/locals
are excluded from warnings because modeled GL calls erase unused arguments.
One compiler worker builds each case sequentially. No new dependencies are
installed; the default contracts use only existing C, shell and AWK tools.

| Seam | Compiled baseline | Patched |
|---|---|---|
| Both QEMU CREATE paths and real queue/response/fence functions | 160 assertions, 48 failures | 118 assertions, zero failures |
| Renderer creator, validator, allocators, destructor, API and resource creation | 23 assertions, two failures | 23 assertions, zero failures |
| Actual Metal/EGL allocation/destruction branches | 25 assertions, three failures | 25 assertions, zero failures |
| Actual GBM/EGL allocation/destruction branches | 25 assertions, three failures | 25 assertions, zero failures |
| Combined QEMU to actual renderer API/resource creation | 58 assertions, 20 failures | 28 assertions, zero failures |

Plain and ASan/UBSan outcomes agree, without sanitizer diagnostics. Baseline
failures are runtime assertions after successful compilation. More baseline
assertions occur because wrongly successful rejected commands enter fence paths.

QEMU checks cover +/-EINVAL, +/-ENOMEM, INT_MIN/INT_MAX, short body, zero and
duplicate IDs, allocation failure, reusable failed ID, initialized wrappers,
full field forwarding, successful publication and ordinary UNREF. Actual
queue/process/response and global/context fence callback functions preserve
original fence ID/context/flags, avoid fencing rejected CREATEs and retire
successful commands once. The original fill macro is compiled unmodified.

Renderer checks execute the actual unknown-internalformat and missing-image
extension failure branches after GL texture acquisition. Conditional builds
execute actual Metal/EGL and GBM/EGL setup/destruction. CUSTOM allocation OOM,
normal host-memory and GL-buffer ownership, staging, MSAA metadata, external
image exclusion, invalid arguments, wrapper/hash OOM and normal table destruction
are covered. Actual from-pipe/API functions preserve one unref on wrapper/hash
failure. Combined contracts check conservation across QEMU and renderer registries.

GL/native calls, allocator failure sites and the hash service are modeled
external boundaries. Pipe/resource structs and QEMU transport structs are reduced
field seams, not ABI-layout proofs. The renderer public arguments, format/target
constants and selected internal arguments are original headers/extracted enums.
Four required YUV aliases are extracted from the original YAML name/alias pairs.
Format conversion tables are modeled; compressed/depth/staging/MSAA forwarding
is not evidence of hardware format acceptance or a real guest backing allocation.
No actual GL, EGL, Metal or GBM runtime is invoked.
Windows/D3D conditional branches are not compiled by these focused checks.

The default QEMU allocation seam models fatal `g_new0` and recoverable
`g_try_new0`; a subprocess verifies normal OOM completion. A separate focused
run can use an already installed GLib library:

```sh
CREATE_SEAMS=qemu GLIB_LIBRARY=/absolute/path/to/libglib-2.0.dylib \
  sh test-create.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-glib-work
```

The macOS check used existing GLib 2.90.0. It calls real `g_malloc0_n`,
`g_try_malloc0_n` and `g_free` at the modeled allocation boundary. Injected
`SIZE_MAX * 2` overflow deterministically exercises fatal versus NULL behavior
without huge allocation. Baseline subprocesses terminate through GLib's fatal
allocator; patched subprocesses complete with OUT_OF_MEMORY. Both plain and
ASan/UBSan reproduce the same QEMU RED/GREEN results. This checks GLib allocator
policy, not physical memory exhaustion or the full QEMU/GLib integration.

Negative guards reject corrupted/missing raw inputs, altered local patches,
wrong archive, existing/relative paths, absent/duplicate/truncated function
extraction and a direct CREATE-overlap overlay challenge. The unchanged IOV
23-case suite is not rerun by this stage.

## Remaining gate

This slice handles already reported CREATE errors and QEMU wrapper OOM.
Some backend calls remain void or return success despite silent GL allocation
failure. Exact renderer OOM classification is not promised because its pointer
API can erase errno. Complete CREATE correctness remains unverified.

SUBMIT/transfer status persistence, decoder sticky errors, context/attach
rejections, fence allocation/wait failure, async delivery and synchronous
reset-before-unmap remain separate required work. Arithmetic/memory bounds,
ANGLE/Metal runtime, the full host build, installation, Mesa 26.2.4 pixel
readback, GPU/NPU acceleration, VM and board behavior remain unverified.
Parent integration owns independent review, native checks and publication,
including companion repository and central EmberBSD overview changes.
