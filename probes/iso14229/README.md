# iso14229 UDS and user-space ISO-TP probe

Build **iso14229 0.11.0** for UDS client/server workflows with its included
`isotp-c` transport. EmberBSD Ports owns the build recipe and installed-consumer
contract. Upstream's major-zero API is unstable; applications must target the
pinned release. See [PROVENANCE.md](PROVENANCE.md) for release-asset selection,
licenses and the upstream AI contribution restriction. Nothing was sent upstream.

NetBSD raw CAN does not provide Linux CAN_ISOTP. This profile explicitly sets
`UDS_AUTOSELECT_TP=0` and `UDS_TP_ISOTP_C`, disabling the release's automatic
Linux socket selection. The software contract delivers real eight-byte ISO-TP
frames between two library instances through a bounded in-memory CAN adapter.
Segmentation, consecutive-frame sequencing, flow control and reassembly use
the included upstream implementation. Physical CAN adaptation is unverified.

## Build and test

Requirements: native EmberBSD/NetBSD, a C compiler, ar, unzip, curl and sha256.
The default compiler is base `/usr/bin/gcc`; CC/CXX overrides are available
for a coherent alternative toolchain. The accepted VM baseline is GCC 12.5.0.
No source generation, Python or external ISO-TP library is required.

```sh
sh probes/iso14229/build.sh /var/tmp/iso14229-probe /absolute/source-cache
sh probes/iso14229/test.sh /var/tmp/iso14229-probe
sh probes/iso14229/tests/build-guards.sh /var/tmp/iso14229-guards
```

Omit the cache argument to fetch upstream. The cache filename and exact hash
appear in [sources.tsv](sources.tsv). All input hashes are checked before
extraction; an existing work path is rejected. The private prefix installs
`iso14229.h` and `libiso14229.a`. Consumers must use the same two transport
macros as the library. They provide `isotp_user_send_can` (including its `arg`
parameter), `isotp_user_get_us` and `isotp_user_debug`.
The supplied consumer demonstrates these callbacks with a monotonic clock.

## Contract and validation boundary

The installed consumer writes and reads 64 bytes via UDS data identifier
`0xf190`. Both request and response require first/consecutive frames and
flow-control acknowledgments, whose counts are asserted. It checks exact
payload bytes, a negative `RequestOutOfRange` response for an unknown DID,
a silent-peer timeout measured with the real clock and successful recovery.
Bounded queues, iteration limits and a process alarm limit failures.

On 2026-10-07, native build/install, the installed consumer and both build
guards passed on EmberBSD/NetBSD 11.0 AArch64 (EMBER64), one vCPU and 3 GiB,
with base GCC 12.5.0. The positive and recovery runs produced 9 request and
18 response consecutive frames. The configured P2 timeout is 500 ms, with a
measured silent-peer bound of 500–2,000 ms; this accommodates VM scheduling.
The consumer links only base libc. Build time was 0.59 seconds; maximum
resident set was 49,960 KiB. Host macOS/Clang smoke also passed.
No Linux socket transport, CAN FD, physical controller/bus, ECU, vehicle,
flash operation, security-access workflow or timing guarantee is validated.
