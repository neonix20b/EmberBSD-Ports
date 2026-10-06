# Provenance

- Original project: [Arm China Compass NPU Driver](https://github.com/Arm-China/Compass_NPU_Driver).
- Revision: `2868d533694740de6891f9998812ceb62a899dee` (2026-04-13),
  `[UMD][KMD].align with 4.3.0 release`.
- Its `Linux/bash_env_setup.sh` declares UMD/KMD 6.1.1. The revision, not that release
  label alone, pins these sources. Archive URL/SHA256: [sources.tsv](sources.tsv).
- Inspection and software-contract checks: 2026-10-07 (local date).
  macOS ARM64/Clang 21 and NetBSD 11 AArch64 VM/GCC 16.2 both pass the
  13-case isolated production-method contract, with the same original RED
  controls. The VM used the committed source export, not a guest-only patch.
  This is not a full UMD/KMD build or hardware/model validation.

The patch modifies only `Linux/driver/umd/src/device/aipu/aipu.cpp` and
`aipu.h`. Upstream Apache-2.0 notices and copyright remain intact; the original
UMD license is copied unchanged in [LICENSE.upstream](LICENSE.upstream).
Pristine `aipu.cpp` SHA256:
`7ece8552372b61ff1004af9342adcd4357b45d7f8987b06c77ce2fe2f4b270b6`;
pristine `aipu.h` SHA256:
`5b79f5c9e777875fc0a24c12ed454e68d9d9d687f35865593b1a3c2f9229f7f6`.

This is a local EmberBSD, AI-assisted correctness patch; it has not been sent
to or accepted by upstream. The regression harness and extraction script are
also AI-assisted; original fragments are compiled from the verified archive,
not rewritten lifecycle algorithms. Helpers are BSD-2-Clause under
[LICENSE.tests](LICENSE.tests); extracted production text remains Apache-2.0.

Factory locking does not prevent another thread from reusing a process-wide
fd. The query-failure regression deliberately allocates a real unrelated file
immediately after the first real close, before the unchanged factory deletes
the object. The tick flag starts false, so this path ordinarily suppresses
the low-level disable ioctl; the erroneous second close is demonstrated
independently. Separate tests cover the original enabled/error tick branch.
