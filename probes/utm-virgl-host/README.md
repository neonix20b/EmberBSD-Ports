# Experimental UTM VirGL host IOV bounds backport

For complete renderer build and direct Metal acceptance, follow the
[private macOS host recipe](host/README.md). It builds on
[classic wait errors](wait-errors.md) and the earlier source stages below.
The QEMU profile and guest acceleration remain disabled.

This probe prepares the accepted upstream IOV-size fix for the current
UTM virglrenderer 1.3.0 dependency, at
[`5d26f605`](https://github.com/utmapp/virglrenderer/commit/5d26f605f50f8e22002ec6db5fb775e1992d4e96).
It helps reject transfers whose backing would appear sufficient after
32-bit truncation. The owner is EmberBSD Ports. This is host dependency
source preparation and a focused software contract, without a NetBSD
package or a complete UTM build.

[`sources.tsv`](sources.tsv) pins original archive/patch URLs and SHA256.
The original [Yiwei Zhang patch](patches/123e0bc-upstream.patch) is unchanged;
it was accepted as upstream
[`123e0bc`](https://gitlab.freedesktop.org/virgl/virglrenderer/-/commit/123e0bc30504c7e745fc008debce30ab0d9a2955),
[MR 1686](https://gitlab.freedesktop.org/virgl/virglrenderer/-/merge_requests/1686).
[`PROVENANCE.md`](PROVENANCE.md) records the mechanical fork adaptation,
existing helper types and license boundaries. Local preparation and checks
are AI-assisted; the fix remains attributed to its upstream author.

## Preparation and focused checks

Supply the original UTM GitHub API archive and a new absolute work directory:

```sh
sh prepare.sh /path/to/utm-virglrenderer.tar.gz /absolute/private/source-work
PYTHON=/path/to/python3 sh test.sh /path/to/utm-virglrenderer.tar.gz /absolute/private/test-work
sh tests/guards.sh /path/to/utm-virglrenderer.tar.gz /absolute/private/guard-work
```

`prepare.sh` verifies the original inputs before extraction or patching.
It preserves the input archive, creates original/patched trees and derives
one patch with the fork's helper spelling and exact hunk locations. It rejects
fuzz, offsets and unexpected output hashes. It never fetches, builds,
installs or enables the renderer. Work directories must be new.

`test.sh` needs a 64-bit host, a C11 compiler with ASan/UBSan, and upstream
Python/PyYAML. Set `CC` and `PYTHON` to existing tools if necessary.
No new project helper is Python. The unmodified upstream Python format
generator produces the actual enum header and full format-description table.
The test compiles the extracted `vrend_transfer_size` and `check_iov_bounds`,
actual inline format-size helpers and original `iov.c`. It includes the actual
pipe resource/box and transfer types. The GL-free resource seam contains only
`base`; the assertion logging seam terminates with `abort`. The minimal
configuration selects host byte order and the real `sys/uio.h`.

On 2026-10-07, Apple Clang 21.0.0 on macOS/arm64 compiled both versions with
`-Wall -Wextra -Werror`. BASE failed five named truncation cases; patched
passed all 23 cases. Both outcomes were reproduced under ASan/UBSan without
sanitizer diagnostics. Cases cover a transfer span above 4 GiB against short
backing, large IOV totals/offsets, oversized default/explicit layer minima,
exact-end/one-byte-short regions, row/layer minima, padding, mip defaults,
R8/RGBA textures and DXT1/DXT5 blocks. Ordinary regions have real small backing;
large cases inspect synthetic length metadata without allocating large buffers
or calling any copy function. Negative checks reject altered archives/patches,
existing/relative work paths and absent/duplicate/truncated function extraction.

## Remaining arithmetic and runtime limits

The accepted fix does **not** certify the complete transfer access path.
The separate `bounds-* limits` observations deliberately retain these issues:

- `util_format_get_stride` returns `size_t` but multiplies two `unsigned`
  values first. RGBA width 1073741825 produces stride 4 instead of
  4294967300. A small two-row box passes with eight backing bytes using that
  wrapped default row; an explicit stride 4 also passes the wrapped row
  minimum when backing metadata covers the large calculated span.
- `info->offset + transfer_size` has no overflow check. Offset `UINT64_MAX-8`,
  span 16 and IOV size `SIZE_MAX` pass this bounds helper after backport.
- `vrend_get_iovec_size` sums in `size_t` without overflow detection:
  `SIZE_MAX+17` wraps to 16. Wider locals preserve ordinary totals above
  4 GiB, but do not repair arithmetic beyond the host size range.

These are helper observations with synthetic large metadata; resource limits
and actual reachability through UTM/QEMU are unverified. Unsigned wrapping
is defined C behavior and does not produce the selected UBSan diagnostics.
No extra renderer fixes are folded into this patch.

Block rounding and `util_format_get_nblocks` also use unsigned arithmetic.
`vrend_transfer_size` uses unchecked 64-bit products/additions; this probe
does not prove their bounds over every possible resource description.
The subsequent read/write paths retain narrow IOV totals, row sizes and
per-layer offsets, plus GL size constraints. Planar/subsampled/depth formats,
Metal conversions, allocation failures, GL errors, renderer-server lifecycle
and alternate GBM paths are outside the focused contract. Main host bounds
failure reports `VIRGL_ERROR_CTX_TRANSFER_IOV_BOUNDS` and returns `EINVAL`,
but that error handling is inspected source, not a compiled runtime check.

## Reported CREATE failure handling

The separate [CREATE source stage](CREATE.md) adds local, AI-assisted patches
for already reported CREATE failures. Both pinned QEMU CREATE handlers reject
short bodies and wrapper OOM, publish resources only after renderer success,
and return an error for any nonzero renderer result. The renderer uses its
existing destructor to unwind owned partial allocations. Ports owns these
patches; they have not been submitted or accepted upstream.

Actual-function macOS/arm64 contracts compile baseline RED and patched GREEN
for publication, response/fence headers, ordinary UNREF and allocator cleanup.
ASan/UBSan pass; EGL/Metal and GBM paths use modeled external calls. A separate
existing GLib 2.90.0 allocator check reproduces fatal versus recoverable behavior
with bounded size-overflow injection. The accepted IOV preparation, source
identity, hash contract and 23-case test behavior remain unchanged.

This handles reported failures only. Silent backend errors, asynchronous
completion/reset, full QEMU and host builds, installation, pixel readback and
acceleration remain unverified. [CREATE.md](CREATE.md) records the seams,
exact source preparation and remaining gate.

The separate [classic backing foundation](BACKING.md) records guest DMA mapping
ownership through actual renderer CUSTOM detach and all cleanup consumers,
including UTM's deferred finish_unmap. Selected-file projection applies all
eight relevant whole UTM overlay sections before accepted CREATE and the local
QEMU ledger patch. Compiled baseline RED, patched GREEN, ASan/UBSan and NDEBUG
contracts pass; removing the deferred consumer's helpers causes a runtime
ownership failure. This source foundation does not qualify reset quiescence
or a complete installed host.

The separate [default-off classic lifecycle foundation](LIFECYCLE.md) adds a
versioned, video-disabled downstream profile, all-resource CPU backing revoke,
generation-aware callback inbox and separate display/native cleanup. Actual-body
RED/GREEN, sanitizer, NDEBUG and causal mutation contracts cover this source
boundary. Pending renderer error propagation and native no-touch/display/host
qualification still prevent enabling it. Existing mixed UTM paths remain outside
this profile's qualification.

The final [reported completion stage](COMPLETION.md) routes returned SUBMIT,
three transfer and global/context fence-create errors into the lifecycle barrier.
The command stays queued until all backing is detached and released; it then
receives its error once. Actual-body macOS/arm64 checks show compiled baseline
RED and patched GREEN in plain, ASan/UBSan and NDEBUG. Silent renderer errors,
full host/native qualification and the accelerated session remain unverified.

The former 0.10.4 recovery host and the UTM beta installation are unchanged.
The private full renderer has direct Apple M3 texture/fence/cleanup acceptance;
there is no installed new QEMU host, enabled guest VirGL, Mesa runtime, GPU/NPU,
VM or board acceleration claim. Parent integration owns publication and the
central EmberBSD overview update.
