# LiteRT-LM CPU Engine source probe

This profile integrates the real C++ Engine API of LiteRT-LM 0.18.0 with the
common LiteRT 2.2.0 CPU runtime. It loads model assets, performs SentencePiece
tokenization, prefill and autoregressive decode, and returns generated text
and token IDs. Ports owns this source integration and its compatibility checks.
It is an experimental source probe, not an installed package.

The first profile selects the upstream `engine_advanced_impl_cpu_only` source
closure. It uses the upstream switches for SentencePiece and disabled NPU. It does not build the Conversation/Jinja API,
HuggingFace tokenizer or Rust bindings. A caller supplies a raw prompt formatted
for its selected model. Audio/vision executor code belongs to the engine's
production closure; audio and vision workflows are not validated by this probe.

## Build integration

Include this directory with `add_subdirectory` after preparing the common
LiteRT runtime and dependencies. CMake never downloads sources. Required values:

| Variable | Contents |
| --- | --- |
| `EMBER_LITERT_LM_SOURCE_DIR` | Verified LiteRT-LM 0.18.0 source tree |
| `EMBER_LITERT_SOURCE_DIR` | Common LiteRT 2.2.0 source tree |
| `EMBER_HOST_PROTOC` | Build-host protoc matching the target protobuf version |
| `EMBER_HOST_FLATC` | Build-host flatc matching the common FlatBuffers version |
| `EMBER_MINIZIP_SOURCE_DIR` | zlib 1.3.2 `contrib/minizip`, unless `minizip` exists |

Required dependency targets are `litert_runtime`, `tensorflow-lite`,
`protobuf::libprotobuf`, `re2::re2`, `sentencepiece-static`,
`flatbuffers::flatbuffers`, `nlohmann_json::nlohmann_json`, `ZLIB::ZLIB`,
`Eigen3::Eigen` and common `absl::*` targets. SentencePiece must use the same
external protobuf and Abseil as the engine. Generated protobuf headers must
be exported by its target. No bundled second copy is allowed.
`cmake/sentencepiece.cmake` provides `ember_add_sentencepiece(source_dir)` for
this composition. It builds the upstream processor, canonicalizes its Abseil
include paths in a build overlay and generates protobuf files with host protoc.

The generated LM protobuf and FlatBuffers files stay in the build tree.
`ember_litert_lm_cpu` is an object library so EngineFactory's static engine
registration is retained without platform-specific whole-archive flags.
`ember-litert-lm` is a real C++20 consumer of this object library. A compile
contract verifies public buffer and tensor return types without permissive
compiler flags. Executables install under the `EmberLiteRt` component.

LiteRT-LM pins a newer LiteRT commit than the current stable 2.2.0 release.
The profile carries a small, byte-identical upstream GatedDeltaNet custom-op
backport. CMake applies it into an isolated build overlay, verifies the four
upstream file hashes, and builds both numerical implementation and LiteRT
registration. It does not replace a missing operator with a stub.
Two LM patches adapt the options accessor names to LiteRT 2.2.0 and exclude
GPU sampler implementation when `LITERT_DISABLE_GPU` is set. Requesting GPU
sampling returns an explicit unsupported error.
A third patch lets a `.task` archive supply the current binary
`ExecutorMetadata` protobuf in an optional `EXECUTOR_METADATA` member.
Missing metadata retains the upstream heuristic. Malformed present metadata
fails explicitly in both static and dynamic executors.

## Run on the target

Run the numerical backport contract and the Engine API consumer:

```sh
ember-gated-delta-test
ember-task-metadata-test /prefix/share/ember-litert/task-state.tflite
probes/litert-lm/test.sh /path/to/ember-litert-lm /path/to/LiteRT-LM-0.18.0
```

The shell contract verifies the upstream fixture SHA256, rejects a missing
file and a malformed file, and compares text and token IDs from two independent
greedy sessions. The fixture exercises real execution, but its training history
is unspecified. Passing it alone does not demonstrate a useful language model.

The Task metadata contract loads small stored ZIP archives through the
production loader. Its CPU graph has KV tensors shaped `[1, 1280, 4, 64]`.
Explicit `sequence_axis: 1` must yield context 1280; absent metadata retains
the upstream heuristic's axis-2 result, 4. Both executor creation paths must
return the parser's error for malformed or empty present metadata.
This synthetic graph tests state layout and error propagation, not inference.

Use a separately identified trained model with SentencePiece for an actual
language task. The production loader accepts `.litertlm` and MediaPipe `.task`
containers. Record the model's upstream URL, revision, license and SHA256:

```sh
ember-litert-lm infer /path/to/model.litertlm 'Your model-specific prompt' 64 2
```

The last arguments are maximum output tokens and CPU worker threads.
Persistent caches are off by default. Set `EMBER_LITERT_CACHE_DIR` to an
existing writable directory to use LiteRT's disk-backed packed weights;
large models may otherwise exceed the board's RAM. The caller owns the
cache files and their cleanup. `verify` repeats the
same raw prompt in independent greedy sessions; `infer` runs one session.
Both return a nonzero status on load, prefill or decode failure.

## Validation boundary

The upstream GatedDeltaNet backport and minizip compile against the NetBSD
AArch64 GCC16 headers. The numerical backport contract passes on macOS/arm64
and the physical NetBSD/AArch64 A733 board used for this port.
The public-header regression fails on pristine LiteRT 2.2.0 and passes after
the common header-qualification patch under GCC 16 with `-std=c++20`.
The common profile builds with the corrected
[GCC16 host prerequisites](../../profiles/development-toolchain/cross/README.md).
The final Engine CLI passes two independent eight-token sessions using the
upstream fixture on that board. The Task metadata contract also passes,
including both malformed-metadata executor paths. See the
[common validation record](../litert/VALIDATION.md) for model identity and
trained-model results. GPU, NPU, Conversation, multimodal input and sustained
runs are not claimed. See [provenance](PROVENANCE.md) for pinned inputs and
patch origins.
