# Full macOS renderer build and Metal acceptance

This experimental Ports recipe builds the complete patched UTM renderer and
current libepoxy 1.5.10 in a private prefix. It makes the earlier
[classic wait source stage](../wait-errors.md) available for real EGL/Metal
checks. Ports owns the recipe and local adaptations, authored with Codex
assistance. It does not install QEMU, change UTM or enable guest acceleration.

## Sources and compatibility

[sources.tsv](sources.tsv) records original archive URLs and SHA256. The renderer
is UTM's pinned 1.3.0 fork `5d26f605`; its selection and the older recovery
host boundary are documented in [CREATE.md](../CREATE.md#version-selection-and-recovery-boundary).
Preparation invokes the accepted IOV/CREATE/backing/lifecycle/completion/wait
chain unchanged. Exact whole renderer files overlay the complete pinned archive;
unmodified translation units, generated headers and Meson are built together.
The separate [paired QEMU recipe](../qemu/README.md) builds the full host and
checks a bounded 2D guest boot; this recipe tests the renderer directly.

Upstream libepoxy 1.5.10 lacks this UTM macOS EGL/ANGLE integration. The patch
rebases UTM commit `bf98587477fe68d07b93319ece7b40a7d0e2eabe` from its 1.5.9 base
onto 1.5.10. It adds framework lookup, EGL support and ANGLE dispatch generation.
The current release's UTF-8, X11/EGL header and Android fixes are preserved.
No older libepoxy is installed. ANGLE registry files and the generator retain
the UTM fork contents and notices; the supplied [ANGLE license](ANGLE-LICENSE)
is installed into the prepared source tree. Libepoxy retains its MIT license.
Mesa 26.2.4 supplies only its original Khronos EGL/KHR headers to this host build.
This is not a Mesa library build or another target Mesa installation.

The renderer's MIT notices and the accepted upstream IOV patch remain intact.
The local `blitter-null-context.patch` adds one null check before the unused
blitter context's destroy callback. Full native cleanup exposed an unconditional
`destroy_gl_context(NULL)`, which caused EGL_BAD_CONTEXT in the embedding host.
Ordinary owned-context cleanup is retained. This local fix and the epoxy rebase
have not been submitted or accepted upstream.

`decoder-truncated-error.patch` also returns EINVAL when a command payload
extends beyond its submitted buffer. Previously the decoder marked its context
in error, broke the loop and returned success to the caller. The patch preserves
the existing bounds check and context error, changing only the returned status.
It is a local, AI-assisted MIT adaptation, not an accepted upstream change.
Already executed commands are not rolled back.

## Reproduction

Requirements: macOS/arm64, Apple Clang, shell, Ruby, ripgrep, AWK, tar, patch,
shasum, current Python with PyYAML, Meson, Ninja and pkgconf. The measured build
used Apple Clang 21.0.0, Python 3.14.8, PyYAML 6.0.3, Meson 1.12.1,
Ninja 1.13.2 and pkgconf 3.0.7. Upstream Python generators remain dependencies;
new project helpers are shell and C under [BSD-2-Clause](../LICENSE.tests). Reuse common host tools rather than building
another LLVM or target toolchain for this recipe.

Download the three original build archives listed in `sources.tsv` and the raw
QEMU inputs in [create-sources.tsv](../create-sources.tsv). No helper downloads
software. Supply existing tools and new absolute work directories:

```sh
sh prepare.sh /cache/utm-virglrenderer-5d26f605.tar.gz \
  /cache/libepoxy-1.5.10.tar.gz /cache/mesa-26.2.4.tar.xz \
  /cache/raw-qemu /absolute/private/host-work

PYTHON=/absolute/path/to/python3.14 MESON=/absolute/path/to/meson.py \
  NINJA=/absolute/path/to/ninja PKG_CONFIG=/absolute/path/to/pkgconf \
  sh build.sh /absolute/private/host-work

sh test-blitter.sh /absolute/private/host-work /absolute/private/blitter-test
sh guards.sh /cache/utm-virglrenderer-5d26f605.tar.gz \
  /cache/libepoxy-1.5.10.tar.gz /cache/mesa-26.2.4.tar.xz \
  /cache/raw-qemu /absolute/private/host-work /absolute/private/host-guards

sh test-native.sh /absolute/private/host-work \
  /absolute/path/to/UTM.app/Contents/Frameworks
```

If PyYAML lives in a private host module directory, export its `PYTHONPATH` for
`build.sh`. The helper exposes the selected absolute `PYTHON` as `python3` in a
private PATH directory. Both Meson discovery and upstream env shebangs use it.
The build defaults to two workers (`JOBS` overrides this), uses nodownload wrap
mode, and installs only under the work directory. It rejects an existing build
prefix. The profile selects EGL, with video/Venus/Neptune/DRM renderers disabled.
The upstream test-suite option is disabled; its tests have not been claimed.

Source, tool, build, exported-symbol, installed-file and DSO receipts remain in
the private work directory. Native acceptance verifies source and installed
checksums before compiling, then checks resolved renderer/epoxy paths and loaded
ANGLE framework paths. It records framework hashes separately: this recipe
uses existing ANGLE binaries and does not rebuild or certify their provenance.
A process needs permission to access the physical GPU. A sandbox that hides
Metal can fail display creation; the helper reports failure, never PASS or SKIP.

## Measured result and boundary

On 2026-10-07, the full renderer and libepoxy built and linked on macOS/arm64.
All three paired classic init/poll/status symbols are exported. The fresh recipe
passed native acceptance with Apple M3, EGL 1.5 and ANGLE Metal OpenGL ES 3.0.
The borrowed frameworks came from the existing UTM 4.7.5 recovery app, not a
rebuilt UTM 5.0.6 host. Runtime ANGLE reports `2.1.22612`, hash `40dfb3a8bd65`.
The exact framework hashes are:

| Framework | SHA256 |
|---|---|
| EGL | `7e05531131d2494576452f7b0735e29a37311f86fded02e5d10bba9037b8428a` |
| GLESv2 | `b1f5f1c162c84e3e590e4f84d7e86c8f1244b49b0debd75c92e7a2c7f7967721` |

Acceptance checks 256 direct EGL pixels, then three complete renderer cycles.
Each cycle creates an RGBA texture, attaches IOV backing, writes 256 nonuniform
pixels, overwrites CPU backing, reads the texture back and compares every byte.
It detaches the exact IOV, releases the resource, waits for a real fence through
the checked polling API, and cleans up. It verifies rejection of live reinit,
conservation of created contexts and continued usability of the caller's EGL
context/display. This is direct renderer API execution, without a guest VM.

The same cycle creates a context and submits actual classic surface/framebuffer/
CLEAR commands for that texture. Red and green alternate between cycles. CPU
backing is replaced with `0xa5` before readback; all 256 RGBA pixels must match
the selected clear color exactly. The context then detaches the resource and is
destroyed before the caller releases its IOV/texture. This checks decoded GPU
commands through Metal, not shader drawing or guest Mesa rendering.

Each cycle also submits six command buffers through the complete decoder with
real EGL contexts. Before the decoder fix, missing payload, truncation after a
valid command and an absent maximum-size payload returned success: three failures
out of six cases. The fixed library returns EINVAL; NOP, opaque END_TRANSFERS
padding and unknown-opcode controls retain their expected results. All six pass
in each of three cycles. This does not prove rollback of a valid command prefix
or all command semantics. The native test is not sanitizer-instrumented.

Before the blitter fix, full native cleanup failed on the absent context. The
small regression compiles the complete original/patched `vrend_blitter_fini`
body with explicit callback/table seams. Plain and ASan/UBSan agree: baseline
has eight checks and four behavioral failures; patched has six checks and none.
The difference is two forbidden null-destroy calls. Owned cleanup and repeated
cleanup are checked. This seam does not validate GL program deletion or ABI layout.
Ten guards reject invalid work paths, missing/altered archives, both patch types/manifest
drift, and changed source/header/DSO files before native execution.

The native renderer warns that ARB/KHR robustness is absent. The short successful
run does not qualify recovery from GPU faults. Native backend error injection, query,
draw, staging/MSAA, initialized blitter lifetime and no-touch-after-revoke
qualification remain open. The full QEMU build and bounded 2D boot are checked
separately; live QEMU decoder-error delivery, reset/BH/display integration, guest
3D DMA and Mesa consumers are unverified. No accelerated EmberBSD session,
Vulkan Compute, NPU execution or target package registration is established.
The host classic profile defaults to OFF; guest VirGL remains disabled.
