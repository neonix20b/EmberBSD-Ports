# LiteRT CPU validation

Validation date: 2026-10-08 (Europe/Moscow).
These results belong to the source profile in this directory and the
[LiteRT-LM integration](../litert-lm/). They do not certify every LiteRT model.

## Build and target

- Sources: LiteRT 2.2.0 and LiteRT-LM 0.18.0, with archives and dependencies
  pinned in [sources.tsv](sources.tsv) and [dependencies.tsv](dependencies.tsv).
- Host: macOS 27.0.1 arm64, Apple Clang 21.0.0, CMake 4.4.4 and Ninja 1.13.2.
- Target compiler: GCC 16.2.0 and NetBSD binutils 2.42, using the corrected
  [Darwin host arithmetic prerequisites](../../profiles/development-toolchain/cross/).
  The clean build used the default eight host jobs.
- Execution: physical Allwinner A733 board, eight CPUs, 4,259,295,232 bytes
  of RAM; device-tree identity `xunlong,orangepi-zero3w`.
  Hardware revision and boot-firmware identity were not independently recorded.
- OS: NetBSD 11.0 / EmberBSD `EMBER64`, built 2026-10-07 09:34:31 UTC.
  Kernel SHA256: `aaaa0443d4e63311091267ffcc8e69a941757b92962720296468936cc695f600`.
- Installation: isolated target prefix, matching `/usr/pkg/gcc16` runtime,
  base libm/libpthread/libz, no `LD_LIBRARY_PATH` override or global installation.

## Contracts passed on the board

| Check | Evidence |
| --- | --- |
| Installed C API | Three changed input pairs, 12 exact float sums; missing/malformed models, invalid signatures/counts and invalid buffers rejected; valid inference recovers |
| Installed C++20 API | The same 12 exact sums, oversized-write rejection and recovery, standalone `LITERT_NO_ABSL` headers |
| Independent SDK consumers | Separate CMake project using only `find_package(EmberLiteRt)` and the installed prefix; both executables run without loader overrides |
| XNNPACK dispatcher | Actual NetBSD dispatcher selects flags `0x13c`; optional ISA bits remain clear |
| GatedDeltaNet backport | Triangular, recurrent and chunk-boundary numerical results |
| Task executor metadata | Actual Task loader and state allocator report context 1280 for explicit axis 1; missing metadata retains heuristic 4; malformed/empty metadata errors reach both executor entry points |
| LM upstream fixture | Missing/malformed models rejected; two independent greedy eight-token sessions agree in text and token IDs |

The fixture test model has SHA256
`36c6cc10f140e5e3526c0838ebb5ce74142b3c0ce8d1356c7d6d0ff50de6a288`.
Its unspecified training history does not establish useful language behavior.
The combined runtime/metadata/fixture script completed in 3.88 seconds;
this short observation is not a throughput benchmark or sustained test.

Host checks also reject a corrupted source cache before extraction, apply
the patches to verified upstream sources and compile strict C++20 headers.
An independent review checked installed headers, license payloads, relative
runtime lookup and the metadata patch; runtime acceptance is recorded above.

## Model identity

The trained input is the Apache-2.0
[TinyLlama-1.1B-Chat conversion](https://huggingface.co/litert-community/TinyLlama-1.1B-Chat-v1.0/tree/7ad278008521e0c4c78192550a698d87a22f395c)
`TinyLlama-1.1B-Chat-v1.0_multi-prefill-seq_q8_ekv1280.task`.
The [preparation helper](prepare-model.sh) verifies the original archive and
migrates its metadata explicitly. Graph, weights and tokenizer are unchanged.

| Artifact | SHA256 |
| --- | --- |
| Original model archive | `0f09dc7f792bb8d49b6629effaee3ed1a99e4506b082cd353471bdf391dee053` |
| Graph and weights | `13eb462f4b83ed920908d4c3fd347f2a0ae8b9795e909dde49a16e1819f622fb` |
| SentencePiece model | `9e556afd44213b6bd1be2b850ebbbd98f5481437a8021afaf58ee7fb1818d347` |
| Prepared METADATA | `9ed9b8a5dda965d0c01e150d97e944a72b51913ee53e8f9447f2239c137e6406` |
| Prepared EXECUTOR_METADATA | `beb7f914fc35aca1fadee4c3408979e110d2310e700ac8dcd45324608f78f130` |
| Host helper output | `1af1afdef197c2f71e4cb559d1373f78aa8d6b4e397b28019f9c7174c0fe587d` |
| Target stored ZIP container | `425fb2b857130416d189cbe5fabca3314d6bde8db73449ecf74ee750e3ab319e` |

The target container was reconstructed with NetBSD bsdtar 3.7.7 from the same
four members to avoid retransmitting weights. ZIP headers differ from the
host helper's output; all four extracted member hashes were verified after
inference and match the prepared content. Models are not in Git.

## Trained-model result

The final CLI completed two independent greedy sessions with two CPU workers,
the raw prompt `The capital of France is` and 16 output tokens per session.
Both text and token IDs matched exactly. The generated text was:

```text
Paris.

2. B. The capital of Germany is Berlin.
```

The runtime selected the graph's 1280-token context from explicit metadata.
The run used an initially empty, caller-owned packed-weight cache:

| Measurement | Observed value |
| --- | --- |
| Whole process, including load, cache creation and both sessions | 63.61 s wall time |
| Maximum resident set (`time -l`) | 2,280,044 KiB, about 2.17 GiB |
| Packed-weight cache (`du -sk`) | 1,015,304 KiB, about 992 MiB |

This establishes real trained-model CPU generation, not general answer quality
or steady-state tokens per second. A preliminary run without the disk-backed
cache reached 3,824,568 KiB RSS and was killed by the kernel's out-of-swap path.
The cache is therefore explicit in the documented 4 GiB board workflow.

## Accepted binary identity

These SHA256 values matched between the staged host output and target files.
Build paths and tools can change output hashes; these identify this run.

| Output | SHA256 |
| --- | --- |
| `libLiteRt.so` | `e075b8c39f0870b91c29574a37dce0b65f2f323928e5360f0ace8511205df984` |
| `ember-litert-lm` | `9bede3e1aea4ca1d4d95fb830bf35adaa39cecd5dbf5f17b86f00e2fef76a750` |
| `ember-task-metadata-test` | `2e96aff9d0b931158c5aaa7c7ec090ce008b1927b279ba3e9231a5ec8fa0216a` |

## Limits

The source profile provides CPU C/C++ execution and the SentencePiece Engine
path. GPU/NPU, Conversation/Jinja, Hugging Face tokenizers, multimodal input,
RISC-V, other boards and sustained operation are unverified.
It is not yet a pkgsrc package or a published binary release.
