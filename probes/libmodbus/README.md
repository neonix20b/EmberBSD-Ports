# libmodbus TCP and RTU source probe

Use current **libmodbus 3.2.0** for Modbus TCP and RTU applications on EmberBSD.
EmberBSD Ports owns this independent source recipe and its installed C contract.
The upstream LGPL-2.1-or-later library is unmodified; exact release provenance
and hashes are in [PROVENANCE.md](PROVENANCE.md).

## Build and test

Requirements: native EmberBSD/NetBSD, a C compiler, GNU Make, curl, tar and
sha256. The consumer uses base libutil for a private pseudo-terminal.
The default compiler is `/usr/bin/gcc`; CC/CXX overrides support a coherent
alternative toolchain. The accepted VM baseline is GCC 12.5.0. `JOBS` defaults
to 1. The official release tarball provides configure; no autoreconf or Python
step is needed. Upstream docs/tests are outside this scoped source build.

```sh
sh probes/libmodbus/build.sh /var/tmp/libmodbus-probe /absolute/source-cache
sh probes/libmodbus/test.sh /var/tmp/libmodbus-probe
sh probes/libmodbus/tests/build-guards.sh /var/tmp/libmodbus-guards
```

Omit the optional cache to fetch the URL in [sources.tsv](sources.tsv).
Hashes are checked before extraction and an existing work path is rejected.
The private prefix installs the headers, metadata and static `libmodbus.a`;
the consumer links this exact archive to avoid selecting a system library.
This disposable source probe is not an installable package. Redistribution
of statically linked consumers must comply with libmodbus's LGPL terms.

## Contract and validation boundary

The installed C consumer uses a dynamically assigned loopback TCP port and
an independently allocated PTY. Both transports write/read holding registers,
check an illegal-address exception, measure a silent-device timeout and close,
reconnect and verify retained register values. RTU uses the PTY master as the
server byte transport and the slave with actual libmodbus connect/termios;
framing and CRC are produced and checked by both libmodbus instances.

Each server is a bounded child process. The parent preserves its exit status,
acknowledges response completion before PTY teardown and waits for cleanup.
Receive timeouts, alarms and kill/reap paths handle failed tests. No physical
serial path, fixed TCP port or permanent device file is used.

On 2026-10-07, native build/install, both installed transport contracts and
both build guards passed on EmberBSD/NetBSD 11.0 AArch64 (EMBER64), one vCPU
and 3 GiB, with base GCC 12.5.0. The configured timeout is 150 ms, checked
within 100–1,500 ms. No test processes remained after completion.
The consumer links only base libutil.so.7 and libc. Build time was 5.08 seconds;
maximum resident set was 48,328 KiB. Host macOS/Clang smoke also passed.
Serial hardware, RS-485 direction control, electrical timing, external PLCs,
physical boards and long-run stability are unverified.
