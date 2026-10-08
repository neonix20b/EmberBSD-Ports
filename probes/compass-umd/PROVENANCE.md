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
  These fragment checks are not full UMD/KMD or hardware/model validation.

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

## Full UMD source adaptation

Patch `0003-netbsd-source-probe.patch` is an AI-assisted local adaptation,
not submitted upstream. It preserves `0001` and `0002`, all pinned UAPI
structure/enum declarations, and all 32 Linux/AArch64 command values.
The NetBSD-only header uses namespaced Linux encoders, with an explicit
little-endian AArch64 LP64 guard. It never replaces native `_IO*` macros.
The original Linux/Android link choices remain; the NetBSD target uses
`libexecinfo`, no `libdl`, and `-z defs`. The Makefile also orders directory
creation before every object, and records complete dependency headers on
NetBSD. `_lwp_self()` supplies the real logging thread ID. The graph change
removes only an unused accumulator and calls to its side-effect-free getter.

The integer/encoding reference is Linux v6.12 commit
`adc218676eef25575469234709c2d87185ca223a`:

- [asm-generic/ioctl.h](https://github.com/torvalds/linux/blob/adc218676eef25575469234709c2d87185ca223a/include/uapi/asm-generic/ioctl.h),
  unchanged test copy SHA256 `5764a3378f017c826ab55382386c5e477c8c8d34ff026cc9e02cff10f2a23bdb`.
- [asm-generic/int-ll64.h](https://github.com/torvalds/linux/blob/adc218676eef25575469234709c2d87185ca223a/include/uapi/asm-generic/int-ll64.h),
  unchanged test copy SHA256 `faca16150492e943a43c83e6b3069531dd498ef15dc612fb2051b88f7da83afc`.

Both reference copies and the adapted UAPI retain
`GPL-2.0 WITH Linux-syscall-note`; they are not covered by `LICENSE.tests`.
The UMD remains Apache-2.0, including its original notices. The full build
uses upstream's vendored header-only ELFIO, whose MIT notice remains intact;
it does not use pybind11 or a simulator SDK. New recipe/consumer/guards are
BSD-2-Clause, AI-assisted, under `LICENSE.tests`.

The official GitHub `main` and release/tag metadata were checked on
2026-10-08: the public head remained `2868d533...`; releases and tags were
empty. The paired 6.1.1 declarations come from that source tree. No newer
public revision was substituted, no SDK account was requested, and no
native driver ABI or model execution is claimed. See [full-umd.md](full-umd.md).

On 2026-10-08 the complete library passed 85 no-device public API checks
over four cycles on the A733 Orange Pi Zero 3W, EmberBSD kernel
`dfe456bf1fba2ec41c0fe11a6a8469b1bd960b99`, with no installed NPU driver.
The target log SHA256 is
`33b95ee733e95cd05f84323a7569bf6617843e990526a614144adceab95737af`.
This proves full-library loading and public failure-path behavior on that
CPU; the native transport and model boundary above remains unchanged.
