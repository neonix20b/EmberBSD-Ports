# dbcppp DBC source provenance

Checked 2026-10-07 against the official
[latest release](https://github.com/xR3b0rn/dbcppp/releases/latest): **v3.2.6**,
published 2022-09-22. This remains upstream's latest release despite its age.
The tag resolves to `54ce78ad53442db94e03d16a4fd5f3b339dab193`.
The exact codeload URL and SHA256 are in [sources.tsv](sources.tsv).

The source is MIT licensed, copyright 2020 xR3b0rn. Preserve its LICENSE.
The release bundles Boost 1.76 headers and refers to libxml2/libxmlmm/cxxopts
submodules. This DBC-only probe instead uses the common **Boost 1.91.0**
header baseline, under the Boost Software License 1.0. Its release commit is
`1a80576db6b70828803819fb6925132193bc5d0e`; archive hash is published by
[Boost](https://archives.boost.io/release/1.91.0/source/boost_1_91_0.tar.bz2.json).
Only the selected headers enter compilation. No Boost shared library is needed.

`CMakeLists.txt` is an EmberBSD-owned build adapter. It compiles upstream's
DBC C/C++ API, parsing, encoding and formatting sources into a private static
archive. It excludes KCD2Network and the command-line tool. This avoids
introducing the release's old XML dependency stack for a DBC-only workflow.
The source patch [dbc-only.patch](patches/dbc-only.patch) removes the unavailable
KCD declaration and makes `.kcd` file loading throw an explicit exception.
It does not substitute successful empty data for unavailable KCD support.

The adapter, patch, shell helpers and consumers were authored for EmberBSD
with AI assistance, under the local MIT [license](LICENSE).
They are local Ports work, not submitted or accepted upstream.
Original authorship and licenses remain unchanged. No upstream Python build
step is used by this adapter. Downloaded archives and binaries stay outside Git.
