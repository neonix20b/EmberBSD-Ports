# Native Metal reset with live classic 3D objects

This experimental probe exercises `virgl_renderer_reset()` in the complete,
accepted [host renderer](README.md), using real ANGLE Metal. Ports owns this
AI-assisted test. It changes no renderer code, UTM installation, guest kernel
or device. The selected renderer remains the pinned UTM `5d26f605` adaptation;
its existing source, installed-file and binary receipts are prerequisites.

## Contract

The public reset API returns `void` and destroys all renderer contexts and
resources. In the pinned implementation, `virgl_renderer_reset()` calls
`vrend_renderer_prepare_reset()`, clears the context/resource tables, frees
fences and blitter state, and replaces ctx0. It leaves renderer initialization
active. A healthy classic wait policy remains active; this test does not inject
or claim recovery from a sticky wait failure.

Each of three cycles performs the following work through the real library:

1. Create ctx8, RGBA resource3 and vertex-buffer resource2. Attach caller-owned
   IOVs and keep their descriptors, payloads and canaries alive through final
   cleanup. Create/bind TGSI shaders and drawing state. Verify the green
   pre-draw target, then submit a triangle with `DRAW_VBO`.
2. Create fence901, 902 or 903. Require that no fence callback has reported it.
   Do not poll, read back, wait or call `glFinish` after creating that fence.
   Call the public reset while the contexts, resources and IOVs are live.
3. Observe destruction of every previous owned EGL context and creation of
   one new ctx0 generation. Require EINVAL from an old-context submission and
   both old-resource information requests. An absent-resource IOV detach must
   leave the output arguments unchanged, as the pinned API specifies.
4. Reject every callback for a cancelled fence, including during later polls.
   Reuse exactly the same context/resource IDs and shader/state handles with
   the existing `native-draw.h` helper. Wait for a new real fence with a
   two-second poll bound; read back 50 magenta interior and 158 green exterior
   pixels. The helper separately checks the 256 green pre-draw pixels and
   validates explicit IOV detach ownership.
5. Check all retired caller backing bytes after subsequent rendering and
   final cleanup. Require balanced owned-context callbacks and render a blue
   pixel through the embedding application's borrowed EGL anchor afterward.

`native-reset-scene.h` adapts the existing draw setup and preserves its Red Hat
MIT notice and pinned upstream test provenance. The harness and shell runner
use BSD-2-Clause, like the other project-owned host acceptance helpers.

## Run

Use an already built and accepted host work directory; do not rebuild the
renderer for this test. The third argument must be a new absolute directory:

```sh
sh native-reset.sh /absolute/accepted-host-work \
  /absolute/path/to/UTM.app/Contents/Frameworks \
  /absolute/new-native-reset-work
```

The runner verifies complete prepared-source, installed-file and binary
receipts before compilation. It checks the accepted draw helper and ANGLE
framework hashes, resolves the actual reset/classic/epoxy symbols and loaded
framework images, and starts the executable with a clean environment. It uses
Apple Clang and the existing host headers/libraries. Ruby supervises only the
owned process group, with a 60-second deadline and five seconds before SIGKILL.
A failed Metal initialization is FAIL, never a successful skip.

The work directory contains the frozen test sources, compiler identity,
compile and runtime logs, linked-library inventory, input hashes, exit status
and output hashes. The runner writes no file into the accepted host prefix.
It reserves a 2 GiB free-space floor plus its 100 MiB work budget, caps the
runtime log at 64 MiB and rejects total outputs exceeding 100 MiB. No download, installation or deployment is performed.

## Evidence and limits

On 2026-10-08, this scenario passed on macOS/arm64 with Apple M3 and the accepted
ANGLE Metal frameworks. Three resets began with two owned GL contexts, two
resources, two attached IOVs and an unreported fence. All three ID-reuse draw
checks passed; eleven owned GL contexts were created and destroyed in total,
and only the three new post-reset fences were reported. Exact input/output
identities accompany the private acceptance receipt.

Two private harness controls use the same unchanged renderer: omitting the
reset fails the context-generation oracle, and explicitly finishing/polling a
fence marked cancelled fails the callback oracle. Both exit 1 with their exact
expected diagnostic. They validate those test oracles; they are not renderer
patches or evidence of a production failure. An initial sandbox run failed at
Metal display creation and is excluded from runtime acceptance.

The observed outstanding state is an **unreported fence and live renderer
objects**. The GPU may already have physically completed the submitted draw.
The test does not prove interruption of in-flight GPU execution, recovery from
GPU faults, no-touch-after-revoke, QEMU reset/BH/display behavior, guest DMA or
an accelerated guest session. The native renderer is not sanitizer-instrumented.
The pixel oracle excludes its existing 48-pixel rasterization edge band.
Guest VirGL remains disabled; the host classic profile remains opt-in.
