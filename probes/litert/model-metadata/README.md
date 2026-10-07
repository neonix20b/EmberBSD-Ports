# Model metadata migration

The pinned TinyLlama `.task` archive uses legacy MediaPipe metadata.
LiteRT-LM 0.18.0's `ExtractOrConvertLlmMetadata` implementation accepts only
the current `LlmMetadata` protobuf message, despite its historical name.
The original archive is rejected with `Failed to parse LlmMetadata`.

`prepare-model.sh` is an explicit build-host operation for this exact input.
It verifies the full source archive hash, encodes `tinyllama.textproto` with
the matching host `protoc`, and replaces `METADATA` in a new archive.
The original file is preserved. The model graph, quantized weights and
SentencePiece tokenizer must retain their hashes in [members.tsv](members.tsv).

Legacy fields 6 and 5 become `start_token` and `stop_tokens`; field 8's user
affixes become `prompt_templates.user`. The stored literal backslash-newline
strings are preserved. The Engine CLI uses raw prompts and explicitly disables
automatic prompt formatting. This is not a general MediaPipe converter.
No token IDs, weights or generated answers are synthesized.

The helper also adds explicit `EXECUTOR_METADATA`. The pinned graph has seven
signatures: `decode` and `prefill_8`, `_64`, `_128`, `_256`, `_512`, `_1280`.
Each has 44 FLOAT32 KV inputs and matching outputs, named
`kv_cache_k_0..21` and `kv_cache_v_0..21`, with shape `[1, 1280, 4, 64]`.
The sequence axis is 1. LiteRT-LM's fallback assumes axis 2 and incorrectly
limits this model to four tokens. The explicit descriptor selects the
existing metadata-based state manager, retaining the real 1280-token capacity.
It does not override the graph's dimensions or relax context checks.

The TinyLlama conversion and model retain their upstream Apache-2.0 license.
The archive revision, URL and checksum are in [models.tsv](../models.tsv).
ZIP tools may produce different container bytes; the helper reports the
derived checksum and verifies the unchanged model members.

The older SmolLM-135M conversion at revision
`dc3dd0de20bff7695054b9918a7e54214ef30c37` was also examined. Its converted
tokenizer contains a NUL piece, rejected by current SentencePiece 0.2.2.
That validation remains enabled; this conversion is excluded from the helper.
See the [upstream model](https://huggingface.co/litert-community/SmolLM-135M-Instruct).
