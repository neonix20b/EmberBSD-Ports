# libmodbus source provenance

Checked 2026-10-07: upstream's
[latest release](https://github.com/stephane/libmodbus/releases/latest) is
**3.2.0**, published 2026-07-02. The tag resolves to
`a9b025d12289855490b10d77461c99e001abfc0f`.
The [official installation instructions](https://libmodbus.org/getting_started/)
recommend the release tarball asset. Its exact URL and SHA256 appear in
[sources.tsv](sources.tsv); GitHub's release asset metadata advertises the same
hash `72239f319b9b8483e3d393c5a60865d734fcff18a8abbb2486e389834a2f6ef1`.

libmodbus is copyright Stéphane Raimbault and contributors, licensed
LGPL-2.1-or-later. The original COPYING.LESSER is retained in the installed
probe metadata; source copyright headers remain unchanged. The private static
archive is for source validation. Distribution of statically linked consumers
requires compliance with upstream's LGPL terms.

No upstream source patches. The official tarball contains configure, so this
build uses the C compiler and GNU Make without autoreconf or Python.
Upstream tests are disabled for this scoped source probe;
its installed TCP and RTU consumers are built separately from Ports.

The shell helpers and C contract are MIT-licensed EmberBSD code, authored
with AI assistance. They are local work; no upstream submission or acceptance
is claimed. Source archives, build logs and binaries stay outside Git.
