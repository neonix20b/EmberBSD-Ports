# Compass UMD descriptor lifetime and core-count probe

This source probe fixes descriptor ownership and public core-count bounds in
the official Arm China
Compass NPU UMD at revision `2868d533694740de6891f9998812ceb62a899dee`,
whose environment declares paired UMD/KMD 6.1.1. It is preparation for an
EmberBSD port, not an installed NPU package or a working NPU backend.
The original source archive and hash are pinned in [sources.tsv](sources.tsv).

`Aipu::init` rejects a valid descriptor zero. On either capability-query
failure it closes a positive descriptor but leaves the stale number owned by
the object. The real factory immediately deletes that failed object; its
real destructor calls `deinit`, closing the number again. Another thread can
allocate an unrelated file with that number between those closes.

The local patch uses `-1` for no descriptor, accepts zero, and invalidates the
member after each close. Error returns, factory flow, memory reference cleanup
and tick-counter cleanup stay unchanged. `deinit` calls the tick dispatcher;
its production branch issues a kernel ioctl only when the atomic tick flag
was true. Ordinary failed initialization starts with that flag false, so the
reproduced harm is the second close, not an unconditional second ioctl.

## Reproduce the software contract

Download the pinned original archive from its public upstream URL, then run:

```sh
sh probes/compass-umd/test-lifetime.sh /absolute/compass-original.tar.gz \
  /absolute/new-contract-work
```

The script verifies SHA256 before extraction, makes separate pristine/patched
trees, applies the patch without fuzz, and compiles both with C++17,
`-Wall -Wextra -Werror -pthread`. `CXX` selects the host compiler. The source
checkout supplied for an audit is never changed. Work/logs stay outside Git.

The compiled fragments are extracted directly from the selected production
files: header member initialization and both factory methods; constructor,
destructor, complete init/deinit bodies; exact error-status enumeration; and
the complete disable-tick switch branch. No method implementation is copied
into the test. Extraction rejects unexpected selector counts/unclosed blocks.

The surrounding class, capability values, memory objects, logging and ioctl
entry points are explicit test doubles. They assert only the fields and calls
used by these methods; they are not ABI headers, a native driver, or an NPU
simulator. Real host `open`, `close`, `fcntl` and immediate descriptor reuse
exercise the ownership boundary. A fresh process isolates every case.

The cases cover the real header sentinel, descriptor zero success and
factory/destructor cleanup, open failure, both query failures with positive
and zero descriptors, an empty capability response, unrelated descriptor reuse
before factory deletion, repeated deinit, and the actual tick false/true/error
branches. Original controls must reproduce the expected diagnostic; unchanged
positive-descriptor destruction and open-error handling remain passing controls.

## Reproduce the core-count contract

`get_core_count` previously accepted indices equal to the partition/cluster
count. A partition query could throw `out_of_range`; a cluster query could
read an absent slot, including one past the fixed eight-cluster array.
Patch `0002` rejects these indices before access. It preserves the `(0,0)`
fastpath: v1/v2 initialization intentionally keeps topology counts zero.
Null/output semantics and the zero-core INVALID_OP result remain unchanged.

```sh
CORE_TEST_SANITIZERS=1 sh probes/compass-umd/test-core-count.sh \
  /absolute/compass-original.tar.gz /absolute/new-core-contract-work
```

The runner verifies the archive, applies both patches with `-f -N -F0`, and
extracts the complete getter, exact LL enum, used member defaults and current
KMD capability structures. Only the surrounding class and initialized states
are modeled. Both `SIMULATION=0` and `1` compile that same production text;
no simulator SDK or simulator initialization is exercised. Unexpected,
duplicate and unclosed extraction shapes fail the runner.

Each branch has 29 patched cases: null output, empty/legacy states, one and
multiple partitions/clusters, equality/larger/maxuint indices, highest valid
indices, branch-specific cluster counts and zero cores. Original logical
controls reproduce six hardware-branch and four simulation-branch failures.
With sanitizers enabled, original cluster index 8 separately triggers UBSan.
`-fstrict-flex-arrays=3` keeps the actual fixed trailing array bounded; it does
not change the header or ABI. Patched ASan/UBSan cases must all pass, without
fallback or recovery. Logs and real exit statuses remain in the work directory.

Sanitizers are opt-in (default `CORE_TEST_SANITIZERS=0`). That mode visibly
skips the original maximum-bound sanitizer proof and never runs its undefined
access unsanitized. It still requires all logical REDs and 29 plain GREENs in
each branch. `CXX` selects the compiler; `CORE_TEST_CXXFLAGS` supplies extra
compiler/linker flags while preserving required warnings. Both plain and
sanitized checks pass on macOS ARM64/Clang 21. Plain checks also pass on
NetBSD 11/AArch64 with GCC 16.2: 29 cases per branch, with the same six/four
original logical failures. The native run took 1.07 seconds, 75,500 KiB peak
RSS and no swaps. Its four binaries resolve one libstdc++.so.7 and
libgcc_s.so.1 from GCC 16.2. Native sanitizer checks were not run; the maximum
original-index sanitizer proof is explicitly skipped in that mode.

## Verified and unresolved scope

On macOS ARM64 with Clang 21 and the NetBSD 11 AArch64 VM with GCC 16.2,
the descriptor-lifetime methods pass all 13 cases. Both platforms
reproduce 11 expected original failures and two unchanged passing controls.
The native VM contract run took 1.08 seconds with 104,048 KiB peak RSS.
This does not establish a full UMD build on NetBSD,
Linux ioctl encoding compatibility, DMA/mapping/coherency, matched kernel
support, board execution, model execution or repeated-inference recovery.
No package, kernel, firmware, compiler selection or board was changed.

The getter patch does not harden malformed capability counts, inconsistent
internal vector/storage state or initialization. ASID bounds and query topology
changes require a separate source and layout contract. The current upstream
four-entry ASID layout must not be confused
with the older CIX vendor ABI. This patch does not address reported historical
second-inference hangs. A matched native KMD/UMD, accessible model toolchain,
real target hardware and repeated inference tests remain necessary.

See [provenance and licenses](PROVENANCE.md). No SDK access request, login,
third-party communication or upstream submission is part of this probe.
