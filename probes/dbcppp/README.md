# dbcppp DBC source probe

Parse DBC files and encode/decode CAN payloads through dbcppp **3.2.6**'s
installed C++ and C interfaces. EmberBSD Ports owns this source probe and its
installed-consumer contract. Release selection, hashes and the local patch are
recorded in [PROVENANCE.md](PROVENANCE.md).

This is an explicit **DBC-only** profile. KCD/XML and the dbcppp CLI are excluded;
loading a `.kcd` file fails explicitly. The probe uses current common Boost
**1.91.0** headers instead of the release's bundled 1.76 headers. No Boost
shared library or old XML stack is installed alongside system libraries.
The complete upstream product and packaging are outside this profile.

## Build and test

On native EmberBSD/NetBSD, install a coherent C/C++ compiler, CMake, make,
curl, tar with bzip2 support, patch and sha256. The default compilers are base
`/usr/bin/gcc` and `/usr/bin/g++`; explicit CC/CXX overrides must use a matching
compiler/runtime closure. The accepted VM baseline is GCC 12.5.0. `JOBS`
defaults to 1. This recipe does not select the separate GCC 16 candidate.

```sh
sh probes/dbcppp/build.sh /var/tmp/dbcppp-probe /absolute/source-cache
sh probes/dbcppp/test.sh /var/tmp/dbcppp-probe
sh probes/dbcppp/tests/build-guards.sh /var/tmp/dbcppp-guards
```

The optional cache contains the exact filenames in [sources.tsv](sources.tsv).
Omit it to download from those upstream URLs. All hashes are checked before
extraction. An existing work path is rejected. The private `install/` prefix
contains `include/dbcppp` and `lib/libdbcppp.a`. Consumers link this exact archive;
no build-tree library or system dbcppp is searched. Boost is a build dependency
only. Preserve the generated environment, linkage and artifact-hash logs.

## Contract and validation boundary

The installed C++ consumer checks a parsed message and fixed known wire bytes:
little-endian and Motorola big-endian signals, signed values with factor and
offset, independent encoding, selector-driven multiplexing for two variants,
malformed streams/files and explicit KCD rejection. The separate C consumer
loads the same DBC and decodes through the installed C API.
The API requires buffers of at least eight bytes; these tests obey that contract.

On 2026-10-07, native build/install and both installed consumers passed on
EmberBSD/NetBSD 11.0 AArch64 (EMBER64) in a one-vCPU, 3 GiB VM, with base
GCC/G++ 12.5.0 and Boost 1.91.0. Malformed-file and both build-guard checks
passed. Dynamic linkage uses only base libstdc++.so.9, libm, libgcc_s and libc.
Build time was 73.71 seconds; maximum resident set was 885,392 KiB.
Host macOS/Clang smoke also passed before the native run.
No CAN controller, physical bus, vehicle, board, long-run stability or real-time
behavior is implied. The fixture is synthetic and requires no private files.
