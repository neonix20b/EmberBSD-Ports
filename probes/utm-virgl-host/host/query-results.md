# Classic query results and delayed errors

`query-output.patch` is a local, AI-assisted MIT adaptation of the pinned UTM
renderer. It has not been submitted or accepted upstream. The complete host
build applies it after the context-error patch and records whole-file hashes.

Query output must fit the resource's logical size and its complete IOV backing
before any write. Nonempty IOV segments need valid bases. The same check runs
again when a pending result becomes ready, because backing can change after
query creation. Detached backing uses the resource's owned private storage;
unreferencing a resource detaches external IOVs before releasing context/global
ownership. A retained query still owns its resource reference.

An immediate result error reaches the command caller. In the opt-in classic
profile, an error discovered during polling latches the checked poll failure.
Already signaled fences remain owned and receive no success callback after
that error. Cleanup releases them; a fresh initialization clears the latch.
Legacy initialization retains its existing polling error policy.

## Full renderer acceptance

On 2026-10-08, the complete renderer passed the native Metal test on Apple M3
using the framework versions and hashes in [the host recipe](README.md).
Each of three cycles passes 17 query checks. The previous renderer reproduced
five failures in the same 17 checks.

The checks exercise actual decoded 32-bit occlusion queries, split IOVs,
private backing, short logical resources, short/replaced IOVs, detached backing
and unreferenced resources. Existing shader, pixel, fence, context-error and
cleanup checks also pass. These native cases do not force asynchronous GL
readiness, exercise 64-bit timer output, or instrument the full library with
sanitizers.

## Delayed-result regression

Use an accepted pre-query renderer tree and the newly prepared renderer:

```sh
sh test-query-poll.sh /absolute/previous-host/renderer \
    /absolute/new-host/renderer /absolute/new-query-test
```

The runner checks the source hashes, extracts complete production functions
and records their selection, source, tool and output hashes. Fake GL readiness,
context and callback seams make pending-to-ready transitions deterministic.
The actual query queue, fence list, checked poll and cleanup bodies execute.
This is a software contract, without a GPU or guest.

Plain and ASan/UBSan runs agree:

| Variant | Checks | Failures |
| --- | ---: | ---: |
| Previous complete renderer | 226 | 32 |
| Bounds repair with previous polling bodies | 226 | 28 |
| Complete repair | 226 | 0 |

The intermediate variant demonstrates that output bounds alone do not repair
error delivery. Cases include 32/64-bit results, replaced short backing,
poisoned contexts, missing subcontexts, empty fence lists, two signaled fences
followed by a pending fence, sticky failure, cleanup and reinitialization.
All variants pass 66 valid pending/ready and legacy control checks included
in those totals. Failure cases check unchanged output, exact fence order and
single deletion. They do not qualify concurrent producers or driver faults.

The default-off host policy remains unchanged. Guest DMA, live QEMU error
delivery, reset/display lifetimes and a Mesa/Wayland session still need
acceptance before enabling guest VirGL.
