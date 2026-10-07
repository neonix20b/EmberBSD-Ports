# LiteRT-LM probe provenance

Sources were checked on 2026-10-07. Upstream copyright and license notices
remain in source archives and patch additions. Source recipes and tests were
prepared with AI assistance. No patch has been submitted or accepted upstream.

| Input | Version / revision | Original URL | Archive SHA256 |
| --- | --- | --- | --- |
| LiteRT-LM | 0.18.0 | https://github.com/google-ai-edge/LiteRT-LM/archive/refs/tags/v0.18.0.tar.gz | `4c0f76dca3ff8d5dca1b1b629f1bf724d295cab9a2bedf8cced60988dcff4df8` |
| LiteRT | 2.2.0 | https://github.com/google-ai-edge/LiteRT/archive/refs/tags/v2.2.0.tar.gz | `6d2ce16738199adc5a3cdde76c3c6a6dac636d3b52a1d7790ea524fb0d59f7fc` |
| minizip sources | zlib 1.3.2 contrib | https://zlib.net/fossils/zlib-1.3.2.tar.gz | `bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16` |

LiteRT-LM and LiteRT are Apache-2.0. minizip retains its Info-ZIP/zlib license
notices. Only minizip is built from the zlib archive; compression links against
the common `ZLIB::ZLIB` provider. The archive does not introduce a private zlib.

## GatedDeltaNet backport

`patches/litert-2.2-gated-delta-net.patch` adds these unmodified production files
from [LiteRT commit 26895c9fbcc25c43faa8c1a98cd1fd28951602c3](https://github.com/google-ai-edge/LiteRT/tree/26895c9fbcc25c43faa8c1a98cd1fd28951602c3/litert/experimental/custom_ops/gated_delta_net):

- `gated_delta_update_impl.cc` and `.h`;
- `gated_delta_update_litert_custom_op.cc` and `.h`.

This is the exact LiteRT revision pinned in LiteRT-LM 0.18.0's WORKSPACE.
Its custom-op registration API is already present in LiteRT 2.2.0.
[Individual source hashes](patches/gated-delta-upstream.sha256) are checked
after every CMake overlay application. The patch keeps Google's Apache-2.0
copyright and licensing comments. Remove the backport when the common stable
LiteRT release includes these operators.

## LM compatibility patches

`lm-litert-2.2-options.patch` maps the new `GetOptions<T>()` convenience API to
LiteRT 2.2.0's corresponding `GetCpuOptions`, `GetGpuOptions`,
`GetQualcommOptions` and `GetGoogleTensorOptions` methods. Both APIs return the
same `Expected<T&>` option objects; this does not change the runtime ABI.

`lm-cpu-sampler-build.patch` makes the GPU sampler implementations respect
`LITERT_DISABLE_GPU`. Those implementations need the newer
`Environment::GetHolderForCApi`, absent from LiteRT 2.2.0. A CPU-only build
returns an explicit unsupported status for a requested GPU sampler. The
upstream CPU sampler is unchanged. Both patches are local EmberBSD adaptations
against LiteRT-LM 0.18.0, prepared with AI assistance and not submitted upstream.

`lm-task-executor-metadata.patch` adds the optional `EXECUTOR_METADATA` member
to the Task resource loader. Its bytes use the unmodified upstream
`runtime/proto/executor_metadata.proto`. The existing `MetadataBasedCreate`
path reads `sequence_axis` and obtains the context size from the actual tensor
dimension. No inferred axis or context-size override is added. The two CPU
executor creation paths propagate present metadata errors; only NotFound and
Unimplemented retain the upstream fallback. This local adaptation was prepared
with AI assistance against 0.18.0 and has not been submitted upstream.

Upstream's Python builder already writes this same protobuf to an
`ExecutorMetadataProto` section in `.litertlm` containers. The Task extension
avoids introducing a separate container writer or Python build dependency.
The model-specific metadata and byte-preserving archive preparation belong to
the [common model recipe](../litert/prepare-model.sh). The synthetic
`tests/task-state.json` and `tests/task-metadata.cc` regression are original
MIT-licensed Ports test code.

The SentencePiece helper uses unmodified processor code after the same
`third_party/absl` include-path canonicalization used by LiteRT-LM's WORKSPACE.
It generates the two upstream protobuf schemas against the common protobuf
version and never compiles SentencePiece's bundled protobuf implementation.

The common runtime's `litert-cxx-name-lookup.patch` qualifies public types in
`litert_buffer_ref.h` and `litert_model_types.h`. It fixes GCC name lookup when
a method has the same name as its return type. The LM header contract checks
the return types under C++20; it does not relax compiler diagnostics.

## Engine fixture

`test.sh` uses the model already included in the pinned LM source archive:
`runtime/testdata/test_lm.litertlm`, SHA256
`36c6cc10f140e5e3526c0838ebb5ce74142b3c0ce8d1356c7d6d0ff50de6a288`.
It is an upstream Engine integration fixture. The archive does not identify
its training history. It proves only the exercised software behavior, not
language quality or the identity of an externally supplied model.

The explicit production source list follows upstream Bazel dependency lists
for `engine_advanced_impl_cpu_only`. It omits conditional NPU, debugger and
HuggingFace implementations through upstream feature switches. The remaining
source files are built unchanged unless an explicit compatibility patch is
listed here. Upstream's floating CMake dependency downloads are not used.
The POSIX platform selections include `worker_thread_pthread.cc` and
`memory_mapped_file_posix.cc`. NetBSD uses their existing portable behavior;
the Linux-specific thread-priority and affinity controls are not enabled.
