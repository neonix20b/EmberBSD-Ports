# Local AI CPU kit

## Purpose and scope

Provide installable native llama.cpp and whisper.cpp executables for EmberBSD,
with a repeatable offline text and WAV transcription demonstration. The initial
validation target is NetBSD-derived EmberBSD 11 on ARM64 in a VM. Physical board
support and accelerated backends require separate evidence.

The user requested the two execution engines. A C+Lua agent, knowledge retrieval,
microphone capture, image models, speech synthesis, and OS image construction
are outside this first engine kit.

## Ownership and packaging

Ports owns native pkgsrc recipes and portability patches. Keep pkgsrc upstream
as a Git submodule pinned to a commit on pkgsrc-2026Q3. A preparation helper may
copy that tree and add local recipes; dependency resolution, source verification,
binary packaging, installation, and removal remain pkgsrc/pkg_tools operations.

Build CPU-only executables using pinned upstream archives. Link each engine's
bundled GGML statically into its executables, without installing conflicting
GGML headers, libraries, or CMake metadata. Link the OS C/C++ runtime normally.
Disable host-specific CPU tuning, optional accelerators, UI downloads, and
unneeded conversion tools. Ship upstream licenses and the source revision.

Examples owns model acquisition and runnable demonstrations. Models remain
separate from executable packages, with immutable source URLs, SHA256 hashes,
sizes, licenses, and attribution. Reusing a download must verify its hash;
failure must not replace a verified asset or create a success receipt.

## Runtime behavior

Text inference reads a local GGUF model. Speech recognition reads a local
Whisper model and a supplied WAV file. A bounded server test binds only to
127.0.0.1 and cleans up its own process. Runtime commands do not fetch models.
An explicit acquisition step is allowed to use the network.

Keep example artifacts in a user-selected directory. Reject invalid paths,
missing models, corrupt assets, and unavailable executables before reporting
success. Preserve nonzero engine exit status and collect relevant logs.

## Evidence

Require native compilation, ordinary pkgsrc package creation, installation into
an isolated test prefix, coexistence of both engines, and actual text and speech
inference. Record OS, architecture, compiler, engine revisions, model hashes,
commands, latency, and peak memory where available. Package installation and
removal must be checked without replacing the active desktop environment.

Deterministic local checks cover configuration and download failures. Model
outputs establish a smoke test, not a quality benchmark. Tests in a VM do not
establish hardware acceleration, audio input, temperature, or board support.

All new repository code and documentation is English and uses no Python.
Existing upstream dependencies and validation limits must be stated explicitly.
