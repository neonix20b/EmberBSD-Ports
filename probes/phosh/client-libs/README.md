# Real Phosh D-Bus client libraries

**2026-10-06: libmm-glib 1.24.2 builds and passes its two upstream tests on
NetBSD 11/aarch64. libnm 1.54.3 does not compile. Neither daemon is ported.**

This directory separates client-library feasibility from daemon support.
It contains no substitute libnm API and no fabricated service state.
All compilation and installation happens as an ordinary user in a new
private directory. No system service, modem, network configuration or
desktop session is changed.

## Build libmm-glib

This optional client-library probe is independent of the final nested
Phosh build profile, which does not require libmm-glib:

```sh
sh client-libs/build-mm.sh /absolute/path/to/new-work-directory
```

Run it from the parent `phosh` directory. The work directory must not
already exist. For offline use, append a directory containing the pinned
`ModemManager-1.24.2.tar.gz` archive. Its checksum is verified in both modes.

The result is installed under `NEW_WORK_DIRECTORY/prefix`:

```sh
export PKG_CONFIG_PATH="$work/prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$work/prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GI_TYPELIB_PATH="$work/prefix/lib/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
```

Set `work` to the work directory printed by the helper. The helper builds
the complete upstream client library, public headers, generated D-Bus
code, introspection data and both library tests. It installs real
`mm-glib.pc` and `ModemManager.pc` metadata. It does not build the daemon,
plugins, libqcdm, CLI or service configuration.

Required tools and libraries include a C compiler, Meson, Ninja, pkgconf,
GLib/GIO, D-Bus headers, gobject-introspection, `gdbus-codegen`, GLib enum
tools, `xsltproc`, curl, tar, patch and NetBSD's `sha256`.
They are already available in the native GNOME build environment.
`JOBS` may be 1 or 2; the default is 2. Upstream Meson and code generators
require Python; `PYTHON` defaults to `/usr/pkg/bin/python3.13` and receives
only a private `python3` symlink. Our helpers are POSIX shell and C.
Automatic Meson subproject downloads are disabled.

The helper copies the parent
[`native-pkg-config.sh`](../native-pkg-config.sh) into its private tools
directory. This selects `/usr/lib/libintl.so.1`, matching the installed
NetBSD GLib/GIO ABI. An absolute `PKG_CONFIG` override is supported.
The external smoke executable's `ldd` output must contain the native
`libintl.so.1` and must not contain pkgsrc `libintl.so.8`.

Each stage preserves its exit status and writes a log under `logs/`.
No source archive, object file or full build log belongs in Git.

## Native results

The probe used EmberBSD's `EMBER64` kernel from OS revision `b4f718d`,
NetBSD 11/aarch64, GCC 12.5.0, Meson 1.11.1 and GLib 2.88.1.

| Check | Result |
|---|---|
| libmm-glib 1.24.2 | Shared library and introspection data built and installed |
| `test-common-helpers`, `test-pco` | Both upstream library tests passed |
| External C consumer | Compiled and linked through the installed pkg-config files |
| gettext dependency | Native `libintl.so.1`; no `libintl.so.8` loaded |
| Real `MMManager` proxy on the system bus | Constructed successfully; ModemManager service name had no owner |
| Modem operations | Not tested; no daemon or modem support established |

To repeat the optional service check with the environment above:

```sh
"$work/mm-client-smoke"
```

It passes `G_DBUS_OBJECT_MANAGER_CLIENT_FLAGS_DO_NOT_AUTO_START`.
Exit 77 means the real proxy was constructed but the ModemManager service
is absent. Exit 1 indicates a bus/proxy error. Exit 0 only confirms a
service owner exists; it does not establish modem functionality.

## libnm feasibility boundary

This independent diagnostic path is not a dependency of `build-mm.sh`:

```sh
sh client-libs/probe.sh networkmanager /path/to/source-archives
```

Omit the archive directory to download the pinned official archive.
This probe attempts a real libnm build and returns nonzero on failure.
It deliberately does not install an unvalidated libnm.

Unmodified NetworkManager 1.54.3 configuration stops at missing `libndp`.
`networkmanager-client-scope.patch` excludes daemon targets and makes
their `libndp` dependency optional. It retains all libraries in upstream
libnm's `link_whole` closure. It also detects `dlopen` in libc before
requiring a separate `libdl`, which NetBSD does not provide.

With these build-only changes, Meson configuration succeeds. Native C
compilation still fails. A keep-going build identified these independent
classes of failure in the client dependency closure:

| Area | Observed incompatibilities |
|---|---|
| Network constants and structures | `linux/rtnetlink.h`, `linux/fib_rules.h`, `linux/if_ether.h`, `linux/if_infiniband.h`, `linux/pkt_sched.h` |
| Native C and networking interfaces | `in6_addr.s6_addr32`, `net/ethernet.h`, `ENONET`, `sys/auxv.h`; glibc `__assert_fail` warnings |
| Time semantics | `CLOCK_BOOTTIME` in client timestamp and common timing code |
| Bundled systemd helpers linked into libnm | Linux btrfs/fs/falloc/oom/random headers, `__NR_getpid`, `stdio_ext.h`, `sys/statfs.h`, `sys/sysmacros.h` |

The first failure without keep-going is `nm-inet-utils.c` accessing
`in6_addr.s6_addr32`. To collect further independent errors from an
existing probe directory, use `ninja -C "$work/build" -j2 -k0`.
These are client compilation failures, not evidence that a running
NetworkManager daemon was attempted.

A real port must separate serialized Linux protocol constants from
native operating-system calls, adapt the required systemd helpers, and
preserve clock, credential, random-number and error contracts. Replacing
missing calls with successful no-ops or mapping suspend-aware time to an
arbitrary clock would not establish these contracts.

The older minimum candidate 1.14.6 was inspected, not built. Its libnm
closure lacks the modern `libnm-systemd-shared` library, but its public
headers still include Linux Ethernet, InfiniBand and VLAN definitions.
Its client/core sources also use Linux traffic-control constants and
`CLOCK_BOOTTIME`. This is a smaller possible porting base, not a validated
fallback or a recommendation to ship an old release.

## Source and patch provenance

Official upstream archives downloaded on 2026-10-06; SHA256 values below
were computed from those downloads and are pinned by the helper.
The GitLab tag snapshots were not checked against a separate upstream
signature or checksum publication.

| Archive | SHA256 |
|---|---|
| [ModemManager-1.24.2.tar.gz](https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/archive/1.24.2/ModemManager-1.24.2.tar.gz) | `fbc75adcc0d7b0565f256e7ff4e8872b0a37c4413ff576665f7470932d9c1b68` |
| [NetworkManager-1.54.3.tar.gz](https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/archive/1.54.3/NetworkManager-1.54.3.tar.gz) | `16c1e954a8598a0afc71c9936a7e4f0ad949522438d96fec63aa1abb6f2207fe` |
| [NetworkManager-1.14.6.tar.xz](https://download.gnome.org/sources/NetworkManager/1.14/NetworkManager-1.14.6.tar.xz), inspection only | `693bcdad15eec7f07a06cbc6e43ddb3b1c13b2d2d23ec165fbb5adf4c3323a5d` |

Both patches are local, AI-assisted build-system changes. They have not
been submitted to or accepted by upstream. They do not change library C
implementations or public APIs. The ModemManager patch retains the
upstream copyright of Iñigo Martinez and adds a `client_only` option;
its common-header pkg-config declaration is taken from upstream's daemon
build file so it remains available when that directory is excluded.
Those Meson files are GPL-2.0-or-later. ModemManager client sources declare
LGPL-2.0-or-later; upstream supplies the LGPL 2.1 text in `COPYING.LIB`.
NetworkManager's modified Meson files declare LGPL-2.1-or-later where
they carry SPDX notices. Original notices remain in the extracted trees.

The upstream license texts are retained in
[`LICENSES/GPL-2.0.txt`](LICENSES/GPL-2.0.txt) and
[`LICENSES/LGPL-2.1.txt`](LICENSES/LGPL-2.1.txt).
The new shell helpers and smoke program use the
[`MIT license`](LICENSES/MIT.txt).
