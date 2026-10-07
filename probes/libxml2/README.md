# libxml2 2.15.4 common source provider

This profile builds the selected current libxml2 release into a project prefix
and verifies an installed C consumer. It provides one explicit XML dependency
for the [SDR profile](../sdr/README.md), without replacing `/usr/pkg` or relying
on the host SDK's older XML implementation.

The current result is a **macOS arm64 host build and installed software
contract**. Native EmberBSD/NetBSD execution and migration of other consumers
remain pending. EmberBSD-Ports owns this recipe and its integration checks.

## Source, API and ABI

The official 2.15.4 archive and SHA256 are pinned in [sources.tsv](sources.tsv).
GNOME published it on 2026-09-04; its release notes are dated 2026-09-01.
No source patch is applied. [PROVENANCE.md](PROVENANCE.md) preserves authorship,
MIT and distinct per-file notices, and the selected build features.

Upstream changed the ELF SONAME to `libxml2.so.16` in 2.14 and restricts binary
compatibility to 2.14 or newer. This recipe preserves that ABI; it does not
provide a replacement `libxml2.so.2`. The current 2.15 series removed the built-in
HTTP client and LZMA support. Existing consumers must be relinked explicitly
and checked before adopting this provider.

The shared build keeps DTD validation, HTML, XPath, XML Schemas, Relax NG,
reader/writer, serialization, XInclude, canonicalization, threads and iconv.
`xmllint` and `xmlcatalog` are installed. Python, documentation, ICU, legacy
APIs, HTTP compatibility and zlib support are disabled. Consequently compressed
XML is outside this profile. No new Python utility is used and upstream's
optional Python binding build remains disabled. Platform iconv/threads are the
only external library facilities selected here.

## Reproduce

Use a new absolute work path without spaces. A populated cache avoids network
access. Without the cache argument, the exact upstream archive is downloaded.
Its SHA256 is checked before extraction; CMake performs no nested source fetch.

```sh
CC=/usr/bin/cc CMAKE=/usr/pkg/bin/cmake JOBS=1 \
    ./build.sh /absolute/new-xml-work /absolute/source-cache
./test.sh /absolute/new-xml-work

XML_PREFIX=/absolute/new-xml-work/install \
    ../sdr/build.sh /absolute/new-sdr-work /absolute/sdr-cache
../sdr/test.sh /absolute/new-sdr-work
```

The build requires CMake, Ninja, a C11 compiler, tar/xz and curl unless using a
cache. `JOBS` defaults to 1; memory limits are inherited. Only an explicitly
provided positive `BUILD_AS_KIB` sets a soft address-space limit. Nothing is
installed outside the work prefix. On macOS arm64, use `HOST_CHECK=1` explicitly.
This host check does not cross-build for NetBSD.

The SDR recipe requires `XML_PREFIX`, checks the provider source inventory,
passes its exact include/library paths to libiio and records the dependency.
Its loader checks reject an unexpected XML provider. Updating the common
provider requires repeating affected consumer contracts; it is not sufficient
to rebuild libxml2 alone.

## Checked result and limits

The 2026-10-07 host run used Apple Clang 21.0.0, CMake 4.4.4 and Ninja 1.13.2.
The installed CMake package was resolved at version 2.15.4 exactly. The C test
checked both runtime version `21504` and `dladdr`'s actual provider path.

The installed C consumer passed tree/attribute parsing, XPath summation and
UTF-8 serialization/reparse. Malformed XML failed with error 76. A 10 MiB text
node failed with `XML_ERR_RESOURCE_LIMIT` (114), without `XML_PARSE_HUGE`.
This is the library's text-node protection, not a universal application input
size limit or an XML security certification. CTest enforces a 15-second limit
and treats nonzero status as failure.

The SDR dependency migration is checked by rebuilding its stack against this
prefix and repeating the installed synthetic IQ and loopback contracts.
Other consumers and native base-compiler/ELF validation are not yet checked.
No global package, physical device or RF scenario is changed by this probe.

Build/test logs, linked-library identity and installed SHA256 inventories are
kept under the private work directory. `tests/build-guards.sh ABS_NEW_WORK`
checks invalid inputs, corrupt sources and missing installations separately.
Public overviews must retain the host-validation qualifier until native and
other affected-consumer results are available.
