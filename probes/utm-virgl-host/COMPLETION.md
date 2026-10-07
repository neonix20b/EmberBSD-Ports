# Reported classic command and fence errors

EmberBSD Ports owns this local, AI-assisted QEMU adaptation. It prevents an
already reported renderer command or fence creation error from becoming a
successful guest response. It follows the [classic lifecycle stage](LIFECYCLE.md)
and keeps `ember-classic-lifecycle` disabled by default. The patch is experimental,
not submitted or accepted upstream. It does not enable or install VirGL.

## Source preparation

The original UTM/QEMU/renderer pins and version exception in [CREATE.md](CREATE.md)
remain unchanged. Preparation invokes the accepted lifecycle stage unchanged,
then copies its QEMU tree and applies one additional delta. The complete original
UTM overlay inventory and all earlier stage receipts remain in the work directory.
[completion-sources.tsv](completion-sources.tsv) pins the exact stage inputs,
local patch and complete output. Complete old hunks must match their recorded
line positions before application; offsets, fuzz and final hash mismatches fail.

Use the same original renderer archive and raw inputs as [BACKING.md](BACKING.md).
Every output directory must be absolute and new:

```sh
sh prepare-completion.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-source-work
sh test-completion.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-test-work
sh tests/guards-completion.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-guard-work
```

The final QEMU files are in `qemu/completion`; the paired renderer remains in
`renderer-lifecycle`. The intermediate `qemu/lifecycle` intentionally retains
its accepted bytes, including its earlier status-handling defects. Shell, AWK,
Ruby, a C11 compiler with ASan/UBSan, ripgrep, patch, tar and shasum are required.
No helper fetches dependencies, modifies an installed host or changes a VM.

## Behavior

Within the opt-in profile, any nonzero result from SUBMIT, TRANSFER_TO_HOST_2D,
TRANSFER_TO_HOST_3D, TRANSFER_FROM_HOST_3D, global fence creation or context fence
creation enters the existing revoke barrier. Positive or negative ENOMEM maps
to OUT_OF_MEMORY. Every other reported value maps to UNSPEC, including INT_MIN;
the implementation never negates an unknown status.

The command records its error before requesting the barrier. This preserves
its status even when callback allocation failure already latched the fault.
Admission stops with the current command still owned by `cmdq`. The error path
creates no subsequent fence, fictitious inflight owner or immediate response.
An already queued callback cannot turn the failure into success.

The existing barrier stops CPU producers, detaches all renderer backing, releases
all QEMU mappings and only then drains commands. The failed command receives its
recorded error once. Other abandoned commands receive UNSPEC unless they already
carry an error. Reset cancels responses. Display block delays native cleanup,
but does not delay CPU backing revoke. These are source contracts under the
lifecycle stage's explicit scheduler, DMA and native-backend premises.

Successful command fields and queue/fence completion behavior remain unchanged.
The 2D transfer keeps its privileged context-zero route. 3D transfers retain
their context, direction and geometry; context fences retain their 64-bit ID.
The profile-off mixed UTM routes retain their original status policy and are
outside this qualification. No new renderer ABI, decoder or guest UAPI is added.

## Causal checks

On 2026-10-07, Apple Clang 21.0.0 on macOS/arm64 compiled baseline and patched
complete production bodies with `-Wall -Wextra -Werror`. Baseline is the accepted
post-overlay/CREATE/backing/lifecycle source, not raw upstream. Each mode runs
683 assertions: baseline has 510 behavioral failures; patched has zero failures.
Plain, ASan/UBSan and NDEBUG agree, without sanitizer diagnostics.

The harness executes the actual four command handlers, dispatch, command queue,
response serialization, lifecycle/revoke, callback inbox and fence completion
functions. It also executes five actual public renderer APIs, including their
lookup failures and context-zero transfer route. A hash-pinned extension reuses
the accepted lifecycle external seams; complete production bodies are extracted
without substitutions. Prepared files, extracted bodies, compiler identity,
compile logs and runtime statuses have private receipts.

Cases cover positive and negative EINVAL/ENOMEM, INT_MIN/MAX; nonfenced, global
and context-fenced commands; successful forwarding/completion; callback before
a failed fence return; callback OOM before the command reports ENOMEM; blocked
display; reset cancellation; missing resource/context lookup; and profile-off
legacy behavior. Backend seams record a completed partial side effect before
returning an error. Observers require every detach and mapping release before
any error response. The side effect is not rolled back or described as hardware
execution. Twelve negative guards reject path, archive, delta, manifest,
input/output identity, coordinate, extraction and accepted-seam drift.

## Remaining gates

This patch only handles statuses which the renderer already returns. It does
not make silent backend failure detectable. SUBMIT short-body/alignment and
allocation handling, decoder length arithmetic/sticky context errors, explicit
transfer validation/bounds, GL/EGL wait tri-state, query output failures and
other context/attach errors remain open. In particular, WAIT_FAILED may still
become completion in the renderer. This patch must not be treated as complete
completion correctness or authorization to enable the profile.

Full QEMU objects and linking, generated headers, paired video-disabled renderer,
actual BQL/BH/reset/display behavior, old-producer absence, native guest-memory
no-touch after revoke, native GL cleanup and repeated initialization remain
required. Backend return/lookup, native GL, transport, scheduler and DMA services
are explicit seams; reduced structs are not ABI-layout proofs. Mesa 26.2.4
query/draw/readback, staging, MSAA, installed-host and accelerated-session
qualification remain pending. Parent integration owns publication and companion
overview updates.
