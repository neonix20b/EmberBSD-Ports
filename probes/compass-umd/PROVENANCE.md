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

Patch `0001` modifies only `Linux/driver/umd/src/device/aipu/aipu.cpp` and
`aipu.h`. Patch `0002` modifies only
`Linux/driver/umd/src/common/device_base.h` to reject count-equal indices,
preserving the legacy `(0,0)` fastpath and existing error/output semantics.
Upstream Apache-2.0 notices and copyright remain intact; the original
UMD license is copied unchanged in [LICENSE.upstream](LICENSE.upstream).
Pristine `aipu.cpp` SHA256:
`7ece8552372b61ff1004af9342adcd4357b45d7f8987b06c77ce2fe2f4b270b6`;
pristine `aipu.h` SHA256:
`5b79f5c9e777875fc0a24c12ed454e68d9d9d687f35865593b1a3c2f9229f7f6`.
Pristine `device_base.h` SHA256:
`1a9bd8436147f147274998d0aec38baaea250b98e4c7d8236bb602c25d933782`;
after patch `0002`:
`ea6fd8300834a859397503e18e2fcee8047fb42f6d4237967d86fe46401baf93`.
Current `Linux/driver/kmd/armchina-npu/include/armchina_aipu.h` SHA256:
`b67ac45075e0473aa96d0e687a990c9696488f3ffe30cd6e2e779971ec3cf929`.
The core-count fixture extracts its actual capability declarations and retains
their `GPL-2.0 WITH Linux-syscall-note` interface license; it does not substitute
the older CIX ABI. Extracted UMD methods/statuses remain Apache-2.0.

These are local EmberBSD, AI-assisted correctness patches; neither has been sent
to or accepted by upstream. The regression harness and extraction script are
also AI-assisted; original fragments are compiled from the verified archive,
not rewritten lifecycle or getter algorithms. Helpers are BSD-2-Clause under
[LICENSE.tests](LICENSE.tests); extracted text retains its upstream license.

The separate core-count contract passes 29 cases per branch with Clang 21 on
macOS ARM64, plain and ASan/UBSan. Original logical controls retain exit 1 with
six hardware/four simulation failures; both original maximum-bound sanitizer
checks retain the real nonzero status and explicit index-8 diagnostic.
The exact Ports `aaeccf9ed3684fdf65ab10a91d49983a81e8cc9d` export also passes
29 plain core-count cases per branch on NetBSD 11/AArch64 with GCC 16.2,
with the same six/four original logical failures. Native sanitizer checks
were explicitly omitted; the original maximum-index proof remains host-only.
The guarded native run completed with status 0 in 1.07 seconds,
75,500 KiB peak RSS and no swaps. Its binaries resolve one GCC16 C++ runtime.
These checks do not establish
full UMD/KMD, simulator SDK, native NPU, model or repeated-inference support.

Factory locking does not prevent another thread from reusing a process-wide
fd. The query-failure regression deliberately allocates a real unrelated file
immediately after the first real close, before the unchanged factory deletes
the object. The tick flag starts false, so this path ordinarily suppresses
the low-level disable ioctl; the erroneous second close is demonstrated
independently. Separate tests cover the original enabled/error tick branch.
