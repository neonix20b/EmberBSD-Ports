# Classic guest backing ownership foundation

EmberBSD Ports owns this local, AI-assisted QEMU source adaptation. It makes
classic guest DMA mapping ownership explicit through ATTACH, DETACH, ordinary
UNREF, resource destruction and UTM's deferred `finish_unmap` consumer. This
is a focused software contract. It has not been submitted or accepted upstream.
Full QEMU objects, native host behavior, reset quiescence and acceleration
remain unverified.

## Preparation

The original UTM/QEMU/renderer pins remain those in [CREATE.md](CREATE.md) and
[create-sources.tsv](create-sources.tsv). Supply the original renderer archive
and the six exact raw inputs, with a new absolute private work directory:

```sh
sh prepare-backing.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-source-work
sh test-backing.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-test-work
sh tests/guards-backing.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-guard-work
```

No helper fetches, installs or enables a host. Source preparation reads the
complete hash-pinned UTM mbox, records every included/excluded file section,
and preserves selected whole sections with their original authors and subjects.
It applies these eight sections in their original order with exact context:

| Original commit | Selected paths, in order |
|---|---|
| `2870e745b902e83ef413ebde08e4c77c7dfead7f` | GPU GL, GPU VirGL, GPU header |
| `3824e0d9968ae9cc4f7809f385615541ed176120` | GPU VirGL, GPU header |
| `3bdba2ae2ed1158b9fc9822562d86b8e287d8490` | GPU VirGL, GPU, GPU header |

Unexpected inventory, selected renames/binary/mode changes, failed/reversed
application, fuzz or offsets fail preparation. Four complete post-overlay
files have pinned final hashes. This is a selected-file projection of the
complete overlay, not a full QEMU integration tree. Excluded `meson.build`
and other sections remain recorded in the manifest and original mbox.

C8b's original raw QEMU CREATE patch retains its bytes and entry contract.
The new stage derives a variant with only hunk coordinates changed: every
complete old hunk must match uniquely and exactly. It compares all other patch
bytes, applies the original patch separately to raw source, checks its accepted
output hash, and compares the three complete CREATE/helper bodies with the
post-overlay variant. This preserves accepted behavior before the ledger stage.
The renderer selected source uses the same accepted IOV adaptation, intermediate
hash and C8b CREATE output hash. Old preparers and suites are unchanged.

## Ownership and failure policy

Successful classic CREATE_2D/3D publishes a zero-initialized private marker.
CREATE_BLOB leaves it false. Managed classic `base.iov` stays NULL/0 so generic
cleanup cannot become a second owner. ATTACH commits the exact array pointer
and actual segment count only after the existing renderer accepts it. Split
DMA mapping can make this count larger than the wire entry count.

Duplicate ATTACH reaches the pinned renderer's existing EINVAL-before-mutation
path. Only the new mapping is freed. DMA partial failure unwinds inside the
actual mapping helper; the caller does not clean it twice. Renderer failures
retain the existing wire response policy. NULL/0 ATTACH remains empty and
allows a later nonempty ATTACH. Counts above INT_MAX are rejected before
renderer narrowing; this guard does not repair the mapping helper's wider
arithmetic limits or introduce recoverable allocator OOM.

`detach_classic_backing` calls the real public renderer detach with initialized
NULL/0 outputs. Mapping storage remains live while actual CUSTOM pipe detach
copies guest bytes into private host storage. The returned array pointer and
nonnegative count must exactly match the ledger. State then becomes
DETACHED_RETAINED. Repeated helper detach does nothing. The release helper
unmaps each segment, frees the array once, clears P/N and returns to NONE.

DETACH, ordinary UNREF, resource destruction and deferred finish_unmap use
this pair. Existing MR grace/command ownership and response ordering remain
intact. Existing nonclassic branches retain their previous behavior.

A broken host ownership contract produces an explicit diagnostic and abort
before guest mapping cleanup, renderer unref or a success response. Releasing
ATTACHED or admitting ATTACH while DETACHED_RETAINED also aborts. This policy
remains active with NDEBUG. It is an internal fail-stop, not a recoverable guest
error or a reset completion mechanism. No valid tested guest sequence produces
such a mismatch. QEMU cannot inspect private pipe IOV state; the actual pipe
chain and its no-op injection contract test cover that separate premise.

## Actual-function checks

On 2026-10-07, Apple Clang 21.0.0 on macOS/arm64 compiled one worker at a time.
Plain and ASan/UBSan results agree without sanitizer diagnostics. The test
extracts complete functions and struct shapes from the prepared full files;
it compiles original renderer IOV copy routines, global resource/API functions,
pipe attach/detach/unref, resource destructor, reference helpers and query
creation/check/destruction. QEMU mapping, cleanup, CREATE, backing handlers,
ordinary UNREF, hostmem cleanup and deferred finish_unmap bodies are actual.

| QEMU conditional branch | Compiled baseline | Patched plain/sanitized/NDEBUG |
|---|---|---|
| VIRGL_VERSION_MAJOR=0 | 49 checks, five runtime assertion failures | 74 checks, zero failures |
| VIRGL_VERSION_MAJOR=1 | 64 checks, five runtime assertion failures | 89 checks, zero failures |

Baseline RED observes the missing explicit ledger through actual `base.iov`
fields after a real successful mapping. It is not a claim of an existing normal
lifetime double-free. Existing CUSTOM and ordinary cleanup cases pass baseline.
A mutant removing only the two new helper calls from actual finish_unmap fails
under both plain and ASan/UBSan builds: the destruction observer finds retained
pipe IOV. Its non-deferred conditional branch still passes.

A second mutant inserts actual guest DMA cleanup before DETACH's renderer
ownership check. It fails the original policy invariant in both conditional
branches and plain/sanitized/NDEBUG builds. Forbidden cleanup, free, unref or
response seams exit with a distinct code, so their failure cannot masquerade
as the production SIGABRT. A direct forbidden-cleanup control verifies this
distinction. Post-commit self-review found and repaired this harness weakness;
the production patch did not change.

Checks cover split mappings, partial failure, duplicate/failed/zero ATTACH,
metadata-only oversized count injection, separate retained detach/release,
repeated DETACH, ordinary UNREF, resource/base destroy, all three hostmem destroy
states and deferred classic/actual HOST3D CREATE_BLOB ownership. The query
retains the actual resource ref; late query completion writes private storage
after guest pages are protected with PROT_NONE. Actual query destruction removes
a linked waiting entry and drops the final resource ref. Six broken-contract
subprocess injections abort with no mapping cleanup, unref or response, also
with NDEBUG. A separate no-op pipe callback injection exposes the private
retention that QEMU's public output comparison cannot itself detect.

The DMA map/unmap, GL result, hash service and MR grace period are external
seams. Allocations use real malloc/realloc/free and small real mmap buffers.
Transport and pipe structs are reduced field seams, not ABI layouts. Renderer
creation for these lifetime tests is a modeled allocation boundary; prior
CREATE qualification remains in its separate accepted stage. GL query constants
are generated seam tokens; this is not a graphics API/format conformance test.
NDEBUG keeps harness assertions explicitly enabled while the production ownership
helpers still use unconditional abort. Oversized count checks use NULL metadata
without large allocation or copying. HOST3D blob checks do not qualify all blob
allocation, guest-backed address-array or export paths.

Thirteen negative guards reject wrong/missing inputs and patches, work paths,
absent/duplicate/truncated extraction, missing shapes, rename/binary projection,
and nonmatching complete CREATE hunk context. Fresh preparations reproduce the
same pinned output bytes. The unchanged IOV/CREATE suites are not rerun.

## Remaining qualification

This foundation does not change SUBMIT/transfer/fence errors, callback ABI,
reset ordering, bulk admission barriers, generation handling or renderer
production code. Resource-destroy checks prove ownership conservation through
the existing reset consumer only. They do not establish producer quiescence.
Full QEMU build and native ANGLE/Metal/GL behavior, threaded/proxy/video/import
paths, remaining bounds, installation, Mesa pixel readback, GPU/NPU, VM and
board qualification remain pending. Parent integration owns publication and
companion overview updates.
