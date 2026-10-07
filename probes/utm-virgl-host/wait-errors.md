# Classic GL/EGL wait error propagation

EmberBSD Ports owns this local, AI-assisted paired QEMU/renderer adaptation.
It prevents failed GL/EGL waits from becoming successful fence completion in
the default-off classic lifecycle profile. The patch is experimental and has
not been submitted or accepted upstream. It follows [COMPLETION.md](COMPLETION.md)
and does not install a host or enable acceleration.

## Cause and behavior

The pinned renderer treated every GL result other than TIMEOUT_EXPIRED as done.
Its EGL fallback treated EGL_FALSE the same way. Native fd polling also accepted
negative poll results and unusable event masks as completion. The resulting
retirement callback could make QEMU answer OK for a fence that had failed.

The wait helpers now return 1 for signaled, 0 for pending and -EIO for failure.
GL accepts only ALREADY_SIGNALED and CONDITION_SATISFIED. EGL accepts only
CONDITION_SATISFIED_KHR. Their timeout values remain pending; unknown results fail.
The native fd path requires POLLIN without POLLERR, POLLNVAL or POLLHUP. Even a
combined POLLIN/error mask fails. Nonblocking EINTR/EAGAIN returns pending after
one poll; the blocking helper retains its interruption retry. The exported fd
is closed once. Classification uses saved errno, before close can overwrite it.

Successful classic initialization enables a single-threaded wait policy. The
first wait failure becomes sticky. The renderer restores any already signaled
prefix to its owned fence list and returns without callbacks or query polling.
Subsequent polls do no further wait work. Full cleanup frees the retained fences
and clears the policy/error; a live repeated initialization cannot clear it.
A direct renderer context poll reaches the same gate through the unchanged
actual decoder retirement callback. That callback is not a SUBMIT wait path.

The new `VIRGL_RENDERER_EMBER_CLASSIC_WAIT_ABI=1` marker declares the paired
`virgl_renderer_ember_classic_poll_v1` and status accessor. QEMU rejects an older
header before capset advertisement/base realize and rejects direct profile init.
Its poll consumes a reported failure before dispatching another command or
allowing callback delivery. The existing lifecycle barrier closes admission,
detaches every backing, releases mappings and then returns UNSPEC. Reset cancels
responses. Display block can defer native cleanup after CPU revoke.

No guest ABI changes. No decoder, transfer or query implementation is changed.
Outside the profile, the existing completion policy still treats wait failures
as completion, including the unqualified worker path. One bounded helper change
also affects legacy nonblocking calls: EINTR/EAGAIN now yields pending rather
than retrying within the call. Ordinary signaled and timeout behavior is retained.

## Reproduction and provenance

The original archive, UTM/QEMU/renderer revisions and version exception remain
those in [CREATE.md](CREATE.md). Each work directory must be absolute and new:

```sh
sh prepare-wait.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-source-work
sh test-wait.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-test-work
sh tests/guards-wait.sh /path/to/original-renderer.tar.gz /path/to/raw-inputs /absolute/new-guard-work
```

Preparation invokes the accepted completion stage unchanged, preserving its
hashes, full selected UTM overlay inventory and preceding source receipts. It
creates separate `qemu/wait` and `renderer-wait` outputs. [wait-sources.tsv](wait-sources.tsv)
pins the added original EGL/list inputs, accepted inputs, both deltas and complete
output files. Complete old hunks must match exact recorded coordinates before
patching. Fuzz, offsets and unexpected output hashes fail preparation.

Requirements are shell, AWK, Ruby, ripgrep, tar, patch, shasum and a C11 compiler
with ASan/UBSan. No helper downloads software or changes installed dependencies.
The original QEMU GPL-2.0-or-later and renderer MIT notices remain in prepared
source. Original Mesa list helpers retain their VMware MIT notice. New helpers
are BSD-2-Clause under [LICENSE.tests](LICENSE.tests), authored with Codex assistance.
No accepting project or upstream has approved these local patches.

## Checked source contracts

Apple Clang 21.0.0 on macOS/arm64 compiled complete extracted production bodies
with Wall/Wextra/Werror. Baseline is accepted completion/lifecycle source, not
raw upstream. Results agree in plain, ASan/UBSan and NDEBUG modes, without
sanitizer diagnostics:

| Contract | Compiled baseline | Patched |
|---|---|---|
| Actual GL/EGL/fd helpers, retirement, public poll/context poll, init and cleanup | 91 assertions, 26 behavioral failures | 126 assertions, zero failures |
| Actual renderer wait through QEMU poll/inbox/revoke/response | 83 assertions, 42 behavioral failures | 83 assertions, zero failures |
| Compiled missing-wait-ABI QEMU branch | Not a baseline failure claim | Two assertions, zero failures |

Additional patched assertions cover the new sticky accessor, bounded interrupted
poll and initialization contracts. Missing new symbols are not baseline RED.
Baseline failures directly observe failed waits generating retirement or success
responses. Tests cover GL_WAIT_FAILED, EGL_FALSE, unexpected results, native fd
errors and masks, both GL signal values, EGL/poll success, timeouts, interrupted
poll, preserved errno, prefix ownership, normal query polling, context/global
fences, 64-bit context IDs, prior queued callbacks, reset cancellation and delayed
native cleanup. The combined tests use actual QEMU response serialization and
require every mapping release before error response.

Twelve guards reject bad paths, missing archive, patch/manifest/input/output drift,
coordinate offsets, absent/duplicate/truncated wait extraction and modification
of the accepted completion seam. The stage records platform/compiler, prepared
and extracted source hashes, compile logs, per-mode runtime logs and statuses.

## Limits and remaining gates

GL/EGL entry points, poll/close, renderer backend initialization, native cleanup
services, scheduler/BQL, transport and DMA remain explicit seams. The tests use
actual list/fence/state definitions and complete function bodies, with reduced
surrounding context structs. They do not prove ABI layout, native waits, locking,
thread shutdown, GL object lifetime or absence of guest-memory touches after
revoke. EGL and GL branches are compiled on macOS; Windows and real graphics
backends are not qualified. Threaded/proxy/video profiles remain excluded.

Full QEMU objects/linking/generated headers, paired renderer build and symbols,
native current-context/reset/BH/display/reinitialization and no-touch evidence
remain mandatory. Decoder arithmetic/sticky context errors, SUBMIT validation,
query output errors, transfer bounds and other silent backend failures remain
open. Mesa query/draw/readback, staging, MSAA and an installed accelerated session
are still unverified. Parent integration owns independent review, publication
and companion overview updates. The profile remains OFF.
