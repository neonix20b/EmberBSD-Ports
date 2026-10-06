# Automotive and AI developer tools

## Scope and design

The requested first stage validates FFmpeg/GStreamer, SQLite and llama.cpp
as native EmberBSD developer dependencies. The second stage adds ONNX Runtime,
ncnn, OpenCV videoio, RNNoise and voice activity detection. Reuse the existing
CPU AI profile and upstream pkgsrc where suitable. Select current supported
upstream sources and record exact revisions, hashes and licenses.

Each component needs an installed consumer, meaningful success/failure cases,
public reproduction instructions and an explicit validation boundary. Use C,
C++ and shell for project-owned code. Upstream Python build dependencies must
be stated. Development probes do not imply package, board or GPU support.

## Execution plan

- [x] Inventory current upstream releases, existing recipes and native tools.
- [x] FFmpeg/GStreamer: reproduce deterministic media encode/decode and an
  installed C/C++ consumer; verify frames, timestamps, EOS and invalid input.
- [x] SQLite: validate installed C API, FTS5, transactions, concurrent readers,
  rollback/reopen and malformed input; preserve evidence of the exact library.
- [x] llama.cpp: extend the current profile with a grounded local-document
  example using SQLite FTS5 and the loopback model server; check absent evidence,
  bounded server lifecycle and an actual model response without external APIs.
- [x] ONNX Runtime and ncnn: build native CPU candidates and run pinned small
  graphs/models against known results; record resource use and CPU fallback.
- [x] OpenCV videoio: reuse the selected FFmpeg/GStreamer stack for a file
  capture/processing workflow. Keep real camera acceptance separate.
- [x] RNNoise and VAD: process deterministic audio, check speech/silence
  boundaries, streaming chunks, output lengths and invalid inputs.
- [x] Review resource/error handling, source provenance and installed linkage.
- [x] Update owning READMEs, public examples, central OS overview and wiki.
  Commit and push only reviewed task files; preserve concurrent work.

## Resource and integration boundaries

Prepare independent component directories concurrently. Serialize heavy native
builds; never reboot or replace packages used by another task. A disposable
native test guest may be used if the shared machine is occupied, and must be
removed after retaining compact evidence. Keep builds and models outside Git.

The integration consumes documented installation prefixes and tools, never
private host paths. No production service or login configuration is changed.
CPU inference is the baseline; accelerators need their own end-to-end tests.

## Review focus

Check silent fallback to another library, truncated media, false PASS after a
failed child, model/server timeouts, database transaction durability, stale
timestamps, source checksum failure and cleanup ownership. Hardware capture,
power loss and real-world model quality require separate measured evidence.
