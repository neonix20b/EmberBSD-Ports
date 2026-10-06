# SQLite source provenance

- Upstream: [SQLite](https://www.sqlite.org/).
- Selected release: **3.53.4**, the current release advertised by the official
  [download page](https://www.sqlite.org/download.html), checked 2026-10-07.
- Source ID: `2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`.
- Archive: `https://www.sqlite.org/2026/sqlite-autoconf-3530400.tar.gz`.
- Size: 3,283,177 bytes.
- SHA256: `0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c`.
- Official archive SHA3-256:
  `454e45f61c6bd75b7420e7190732dea03ce6639c63ada47bbc592f67fc340338`.
- SQLite deliverables: [public domain](https://www.sqlite.org/copyright.html).
  Upstream's source header retains its public-domain dedication. The archive's
  autosetup helper has a BSD-style license, preserved by the build helper.
- No SQLite source patches. This directory's C/shell checks are MIT licensed,
  written for EmberBSD with AI assistance. No upstream acceptance is claimed.

The pinned pkgsrc-2026Q3 tree already supplies SQLite 3.53.4 in
`databases/sqlite3`; do not add another permanent SQLite version. `build.sh`
provides a disposable native source probe when replacing an active shared
system dependency would interfere with other work. Its prefix is removed
after retaining evidence. It is not a second system installation or a package.

The existing validation VM has pkgsrc SQLite 3.53.2, source ID
`2026-06-03 19:12:13 d6e03d8c777cfa2d35e3b60d8ec3e0187f3e9f99d8e2ee9cac695fd6fcdf1a24`.
That installed consumer is separately identified in the result. An older
cached search result described 3.53.2 as latest; the direct upstream download
metadata and the pinned pkgsrc recipe establish the newer target.
