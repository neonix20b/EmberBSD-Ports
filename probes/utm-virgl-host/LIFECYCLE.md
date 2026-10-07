# Default-off classic VirGL lifecycle foundation

EmberBSD Ports owns this local, AI-assisted downstream source adaptation.
It establishes a CPU guest-backing revoke boundary before terminal callback
allocation failure responses and reset completion. It is not an enabled host,
complete error-handling implementation, native safety qualification or package.
The patches have not been submitted or accepted upstream.

## Profile and compatibility

`ember-classic-lifecycle` defaults to false. Enabling the property requires
the paired downstream renderer ABI `VIRGL_RENDERER_EMBER_CLASSIC_LIFECYCLE_ABI=1`
and `virgl_renderer_ember_classic_init_v1`. An older renderer header makes
realize reject the profile before capset advertisement or base realize.
The guest ABI is unchanged. The renderer must be built with `-Dvideo=false`;
an `ENABLE_VIDEO` build rejects this entry point before initialization.

The profile excludes Venus, Neptune, blobs, hostmem, resource UUID and dmabuf
export. It exposes classic VIRGL/VIRGL2 capsets and rejects unpublished capsets,
invalid context-init bits/IDs and unnegotiated or nonzero ring indices.
Prohibited command routes fail before forcing renderer context zero.
CUSTOM, queries, COPY_TRANSFER/staging, MSAA and ordinary formats remain
available; no new QEMU format or renderer-command decoder is introduced.

The renderer flags are restricted to zero or NATIVE_SHARE_TEXTURE (4096).
THREAD_SYNC, ASYNC_FENCE_CB and proxy policy are disabled independently of
`has_eventfd`. The callbacks enqueue into QEMU's inbox, but the renderer
producer executes on the calling poll thread. This does not claim that
ANGLE, Metal, EGL or the native graphics driver have no internal workers.

Existing mixed UTM routes retain their separate owners, including deferred
MR/UNREF completion. They are outside this profile's lifecycle qualification.
The pins and temporary renderer-version exception in [CREATE.md](CREATE.md)
remain unchanged; this does not introduce another supported renderer release.

## Ownership and ordering

The classic lifecycle is separate from the existing mixed renderer state.
Admission closes under BQL before base reset. The main-loop revoke requires
no active renderer call and no command-queue processing. Every resource is
prechecked for the C8c1 managed marker and absence of nonclassic owners.
Violations abort before any detach, release or response, including NDEBUG.
The accepted exact pointer/count checks remain unconditional.

One complete pass detaches every renderer IOV. Only the next pass unmaps and
releases QEMU's backing arrays. Renderer CUSTOM copies therefore complete while
all guest mappings remain live. Fault drains answer each command once using
its recorded error, or UNSPEC. Reset drains free commands without responses;
fence-queue ownership alone decrements inflight. Unparsed terminal commands
receive a bounded real wire-header decode; short headers cannot invent fences.

Display block does not prevent CPU backing revoke or reset_finished. It delays
scanout teardown, resource_unref and renderer cleanup. The wrappers retain only
the previously admitted resource set. Cleanup runs after unblock, with all
resource unrefs before renderer table destruction. Reset then permits a fresh
lazy init and reschedules the control BH so an earlier kick is not lost.
`reset_revoke_done` separates a requested reset from completion of its resource
hook; a lifecycle BH cannot bypass that hook.

An inbox allocation failure is the first real terminal-fault ingress. The
profile uses `g_try_new`, a preallocated sticky latch and an already owned BH.
The callback does not revoke recursively. Faults raised by a test handler are
explicit lifecycle-contract injections, not evidence of renderer error coverage.
Records carry generations; stale records cannot complete new commands. Reset
wins over pending fault/success delivery. Generation exhaustion aborts instead
of wrapping. Callback defaults are restored before each fresh initialization.

BH/timer/list ownership starts once after successful base realize, before the
first renderer init, and ends at unrealize. Failed initialization drains inbox
records; successful initialization preserves an OOM latch raised by a callback.
Unrealize revokes backing first. A live renderer with blocked display then
fail-stops before deleting handles/device ownership or making native GL calls.
Completing that hot-unplug normally requires a later native display-drain contract.

Polling runs every 1 ms of QEMU_CLOCK_VIRTUAL while RUNNING, including empty
command/fence queues. Blocked display prevents renderer calls; unblock resumes
polling. Renderer query checks precede the empty-retired-fence return and fence
callbacks. There is no latency guarantee during VM pause or display block.

External EGL cleanup frees the renderer's wrapper independently of GBM, clears
its globals, and frees an external-init GBM object when present. It never calls
`eglTerminate` on QEMU's display. Owned EGL/GLX cleanup retains its existing path.

## Reproduction and provenance

Use the same cached original archive and six raw inputs as [BACKING.md](BACKING.md).
Each work directory must be absolute and new. No helper downloads, installs,
changes a VM or modifies an installed UTM.

```sh
sh prepare-lifecycle.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-source-work
sh test-lifecycle.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-test-work
sh tests/guards-lifecycle.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-guard-work
```

Requirements are a C11 compiler with ASan/UBSan, shell, AWK, Ruby, ripgrep,
tar, patch and shasum. Project helpers do not use Python. Tests are sequential
and use small buffers. `lifecycle-sources.tsv` pins original extra archive
members, accepted stage inputs, delta patches and complete output files.
The original URLs, commit and archive checksum remain the accepted source pins.
Previously patched files are never relabeled as originals.

Preparation invokes the unchanged accepted backing stage, retaining its full
selected overlay inventory and original mbox. It adds the pinned base GPU source
as a read-only input. Before each local delta, complete old hunk text and counts
must match the exact original line positions. This check is independent of patch
logging: Apple's patch can silently accept a coordinate offset. Fuzz, failed
application and unexpected final hashes also fail preparation.

## Checked source contracts

Apple Clang 21.0.0 on macOS/arm64 executes extracted complete production bodies.
Baseline is post-full-selected-UTM-overlay plus accepted C8b/C8c1, not raw upstream.
Baseline reset compiles and fails a release-before-final-detach assertion using
actual reset, resource-destroy and ledger bodies. Baseline renderer compiles and
fails pending-query progress and external EGL wrapper-release assertions.
Missing newly proposed APIs are not counted as baseline RED.

| Contract | Plain, ASan/UBSan, NDEBUG result |
|---|---|
| QEMU lifecycle, queue/inbox ownership, policy and reset paths | 86 checks, zero failures |
| Actual renderer init/poll/query scheduler and external EGL without GBM | 10 checks, zero failures |
| The same external EGL path with GBM | 10 checks, zero failures |
| Renderer built with ENABLE_VIDEO | 6 checks, zero failures |
| Actual C8c1 mapping/API/pipe/query with the new revoke body | 4 checks, zero failures |

The QEMU suite includes callback OOM during poll/init, fault during a handler,
callback before fence ownership handoff, context/global isolation, cumulative
out-of-order completion, u64 context fences, stale generations, both fault/reset
orders, blocked reset/unrealize, full-resource precheck, repeated/failed/never-init
lifetimes, callback-default restoration and a control kick across cleanup. A callback fault
during initial init also re-kicks the unread descriptor after CPU revoke, even
when display block delays native cleanup.
The command queue uses separate admission and post-dispatch handoff hooks.
A display block stops the next command but permits current response/fence
ownership handoff. A fault/reset still retains the current command for revoke.
The dispatch seam raises display block for non-fenced, global-fenced and
context-fenced commands; actual queue/callback bodies verify single completion.
A separate compiled old-ABI branch rejects the opt-in property.

Seventeen causal mutants fail behavioral assertions in all three modes: release
per resource; skip second detach; lost OOM latch; absent generation comparison;
THREAD_SYNC; prohibited-command gate; fault ownership handoff; display-block
ownership handoff; cleanup under block; responses after reset; missing persistent rearm; public producer gate;
missing resource precheck; blocked-unrealize deletion; stale callback defaults;
early query return; and the former GBM-only external cleanup.
Forbidden release/response/device deletion seams use a distinct exit status,
so generic abort cannot masquerade as a successful fail-stop policy check.
Twelve negative guards reject source/delta/manifest drift, relative/reused work
paths, coordinate offsets and absent/duplicate/truncated extraction.

The scheduler/BQL, timer/BH, DMA and display/native GL boundaries are explicit
external seams. The vCPU wait seam invokes the actual reset BH synchronously;
it does not prove actual locking or thread serialization. Renderer-init backend
allocation and worker flags are observed through seams. Full GL/command/resource
objects and ABI layout are not reconstructed. Actual command, GL-device and
ledger struct definitions are extracted; surrounding framework types are reduced.

The backing integration reuses a hash-pinned C8c1 harness with only external
seam types extended. It runs real mapping, global resource APIs, pipe detach,
CUSTOM copy, query/ref consumers and the new complete revoke body. A pending
query writes private storage after guest pages become PROT_NONE. The separate
multi-resource lifecycle test checks all-detach ordering and the second-detach
mutant; it uses a renderer detach observation seam. Neither establishes native
host IOV non-aliasing. Accepted C8c1 helpers and tests remain unchanged.

## Remaining gates

Do not enable this profile or describe it as a safe accelerated host yet.
SUBMIT/transfer/fence-create status, decoder arithmetic/sticky errors, GL/EGL
wait tri-state and query output failures remain open. Existing context-fence
creation failure can still answer OK; WAIT_FAILED can still become completion.
These failures must enter the verified barrier in a later error-handling slice.

Full QEMU objects/linking with generated headers, paired renderer ABI and actual
video-disabled configuration remain required. Native work must establish the
current-context, BQL/reset/BH/display block/unblock and repeated-init contracts,
absence of old renderer producers, and guest-memory touches after revoke/unmap.
Absence of crashes, glFinish or a timeout is insufficient evidence of no-touch.
Mesa 26.2.4 query/draw/readback, staging, MSAA and the other host qualification
gates remain pending. No installed-host, VM, board, GPU/NPU or pixel claim follows
from these source contracts. Publication and overview integration belong to the
parent task.
