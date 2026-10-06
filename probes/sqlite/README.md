# SQLite installed C consumer

Validate SQLite as a native dependency for local device data and document
retrieval. The current upstream target is **3.53.4**, already present in the
pinned pkgsrc `databases/sqlite3` recipe. This probe adds a C consumer and
repeatable checks; it does not introduce another permanent SQLite version.
See [source provenance](PROVENANCE.md) for the archive, hashes and license.

## Existing installation

With the intended SQLite's `sqlite3.pc` visible to `pkg-config`:

```sh
PATH=/usr/pkg/bin:$PATH sh probes/sqlite/check.sh /var/tmp/sqlite-check
```

The output directory must be new. `check.sh` requires 3.53.4 by default;
an explicit `SQLITE_EXPECT_VERSION=3.53.2` permits the documented older
comparison. The C consumer requires matching compile-time and runtime source
IDs, records native library linkage, and never overwrites an existing database.
Its database and logs remain in the private result directory.

## Disposable current-source comparison

Use the ordinary pkgsrc recipe for the system package. When that would replace
a library used by a running desktop or other work, a disposable native source
prefix can establish the current library's consumer behavior:

```sh
PATH=/usr/pkg/bin:$PATH sh probes/sqlite/build.sh /var/tmp/sqlite-current
prefix=/var/tmp/sqlite-current/install
PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" LDFLAGS="-Wl,-R,$prefix/lib" \
    PATH=/usr/pkg/bin:$PATH sh probes/sqlite/check.sh /var/tmp/sqlite-current-check
```

`build.sh` requires native NetBSD/EmberBSD, C, GNU make, curl, tar and sha256.
An optional second argument supplies an existing archive directory. Every
archive must match the pinned SHA256 before extraction. The helper configures
thread safety and FTS5, leaves built-in JSON enabled, and compiles with one
low-priority job. Upstream autosetup builds its bundled C Tcl helper if needed;
this configuration has no Python dependency. No system files are replaced.

The prefix exists only for comparison. After recording linkage and checks,
remove that run's disposable build directory; do not keep it as an application
dependency. Updating a shared system SQLite requires checking its actual
consumers; these probes do not replace that coordinated upgrade.

## Checked behavior

The C executable tests prepared parameter binding with SQL-looking text,
FTS5 lookup and absence, JSON extraction, malformed FTS/JSON rejection, explicit
transaction rollback, and WAL snapshot isolation across two connections.
It then forks with all database connections closed. A child begins an
uncommitted write and spills pages; a separate parent connection can still
read the last committed data. The parent kills only that child with `SIGKILL`,
reopens the database and checks that committed data survived, uncommitted data
did not, and `integrity_check` is `ok`. A 20-second alarm bounds the executable.

This establishes **process crash and reopen**, not physical power-loss
durability, flash behavior or storage-controller correctness. WAL does not
establish every journal mode or filesystem. No claim of the upstream full
SQLite test suite is made.

## Results

On 2026-10-07, the installed pkgsrc SQLite **3.53.2** passed the complete
consumer on EmberBSD/NetBSD 11.0 AArch64 (UTM, GCC 12.5.0). Headers and runtime
reported the same exact source ID. `ldd` resolved SQLite to the selected
`/usr/pkg/lib/libsqlite3.so`; no bundled SQLite implementation was used.

The [local-document example](https://github.com/neonix20b/EmberBSD-Examples/tree/main/ai/local-knowledge)
also used this installed library for FTS5 retrieval, response JSON validation
and an actual single-threaded llama.cpp answer. That is a separate application
consumer, not merely a library configuration result.

The current **3.53.4** archive was then built with GCC 12.5.0 and installed
in a disposable EmberBSD/NetBSD 11.0 AArch64 QEMU guest (one vCPU, 3 GiB RAM).
The complete C consumer and independent local-knowledge contract tests passed.
`ldd` resolved both consumers to that temporary 3.53.4 prefix, and headers and
runtime matched source ID `bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`.
The real model answered the retrieved pump question using this current SQLite
in 3.78 seconds, with 219,272 KiB maximum RSS for the wrapper and its children.
The final parser/contracts and model run also passed during concurrent build
load: 15.11 seconds and 217,116 KiB. Neither run is a performance benchmark.
The VM's existing EMBER64 kernel was built from OS revision
`b4f718d`; neither library test changed the kernel or a physical device.

Physical boards, power loss and production database load remain outside this
VM probe. Project-owned code and tests are [MIT licensed](LICENSE).
