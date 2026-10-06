# Native Phoc compositor probe

Phoc 0.58.0 and gmobile 0.7.4 compile on EmberBSD/NetBSD 11 aarch64.
The compositor runs with the wlroots 0.20.2 X11 backend and pixman renderer
inside an existing X11 desktop. On 2026-10-06, all 19 Phoc Meson checks
and all 7 gmobile test suites passed. This establishes a nested compositor,
not a complete mobile session, GPU acceleration or hardware display support.

These Phoc and wlroots versions match the
[official Phosh 0.58.0 release](https://phosh.mobi/releases/rel-0.58.0/).
Layer-shell, Phosh private protocols, thumbnails and xdg-shell are exercised
by the upstream Phoc tests. The compositor's direct GLES dependencies are
unused; the local patch removes those dependencies and headers. Rendering
continues through wlroots's normal renderer API.

## Reproduce

Use the native NetBSD 11/aarch64 development environment and pkgsrc packages
from the `11.0_2026Q2` catalog. Required tools include a C compiler, Meson,
Ninja, pkgconf, curl, gettext tools, GLib tools and gdbus-codegen.
Upstream Meson and code generators use Python; this shell helper creates
a private `python3` link, defaulting to `/usr/pkg/bin/python3.13`.
Set `PYTHON` to an absolute interpreter path if needed.

Dependencies include Wayland >=1.24, wayland-protocols >=1.47, libdrm
>=2.4.129, pixman >=0.43.4, xkbcommon >=1.8, GLib >=2.80, json-glib,
gnome-desktop3, gsettings-desktop-schemas, libopeninput (`libinput.pc`
>=1.27), libudev-bsd, seatd (`libseat.pc`), hwdata, libdisplay-info and
XCB libraries. Xvfb and D-Bus are needed for the protocol tests.
The build finds installed libraries under `/usr/pkg` and `/usr/X11R7`.
It does not need a GLES implementation or system package replacements.
The shared `../native-pkg-config.sh` wrapper selects `/usr/lib/libintl.so.1`,
matching the installed GLib ABI. This avoids mixing it with pkgsrc libintl.so.8.

Copy the entire parent `phosh` probe directory, then run from its `phoc` subdirectory as an ordinary user:

```sh
sh build.sh "$HOME/.cache/phoc-native"
sh test.sh "$HOME/.cache/phoc-native"
```

The build directory must not already exist. Optionally pass an archive
directory as the second build argument. Both modes verify the pinned
SHA256 values before extraction. `JOBS` defaults to 2. Meson downloads
are disabled. Failures preserve their exit status and print the log path.
Sources, archives, full logs and products remain in the private directory.
The installed prefix is `BUILD_DIRECTORY/prefix`.

The helper first tests and installs gmobile. It builds the wlroots sources
bundled in the Phoc release, applying the exact five patches named in
`subprojects/wlroots.wrap`. It then builds and installs Phoc. DRM,
libinput and session APIs are compiled because Phoc references them;
the tested runtime explicitly selects X11. GLES, Vulkan, GBM allocation
and Xwayland are disabled. Shared-memory allocation and pixman remain.

`test.sh` starts its own 2048x2048 Xvfb, selects a free display number,
runs Phoc's checks and stops only that server. Tests need a larger virtual
display than the nested demo: a desktop window manager may constrain their
expected 1024x768 or 1080-pixel outputs. The active desktop is untouched.

## Nested run

From the existing X11 desktop, with its normal `DISPLAY` and X authority:

```sh
work="$HOME/.cache/phoc-native"
export PATH="/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin"
export LD_LIBRARY_PATH="$work/prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
export XDG_DATA_DIRS="$work/prefix/share:/usr/pkg/share:/usr/share"
export XDG_RUNTIME_DIR="$work/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
WLR_BACKENDS=x11 WLR_RENDERER=pixman dbus-run-session -- \
  "$work/prefix/bin/phoc" --config "$work/nested.ini" \
  --socket emberbsd-phoc --no-xwayland --verbose
```

The supplied configuration requests 360x540. The tested 800x600 GNOME
desktop constrained this to 360x531 to accommodate window decorations.
Clients use the same runtime directory and `WAYLAND_DISPLAY=emberbsd-phoc`.
Launch a shell using Phoc's `--exec` option when both must share the private
session bus. Phosh should have a separate bus from the host GNOME session.
This recipe does not modify `.xsession`, log out or reboot the host.

## Patches and boundaries

All local changes are AI-assisted and have not been submitted upstream.

| Patch | Reason and check |
|---|---|
| `gmobile-wakeup-unsupported.patch` | Return `G_IO_ERROR_NOT_SUPPORTED` when `CLOCK_BOOTTIME_ALARM` is absent; regression checks zero source ID and the error |
| `gmobile-device-tree-test.patch` | Test the implementation's existing non-Linux unsupported result; same adjustment as the sibling gmobile 0.1.0 probe |
| `phoc-portability.patch` | Remove unused GLES includes/dependency, guard Xwayland-only references and fix a missing semicolon in the non-Linux pidfd branch; native compilation and protocol tests pass |
| `phoc-test-portability.patch` | Find `true`/`false` through the already enabled search path and run the POSIX lint script with `/bin/sh` |
| `wlroots-x11-atoms.patch` | Create X11 atoms before using them; an absent `_VARIABLE_REFRESH` otherwise causes `BadAtom`; isolated Xvfb and nested GNOME run without this error |

Ordinary gmobile timeouts retain upstream's BSD mapping from
`CLOCK_BOOTTIME` to `CLOCK_MONOTONIC`. They do not establish suspend-aware
elapsed time. Wakeup timers explicitly fail; no wake clock is substituted.
Device-tree discovery and Linux pidfds remain unsupported.

The tested renderer uses shared memory and software composition. The X11
server reports no DRI3; Phoc reports Linux dmabuf unavailable. These are
expected capability boundaries, not evidence of GPU support. KMS, suspend,
input hardware, mobile services and a complete Phosh session require
separate verification. This directory does not claim those results.

## Provenance

[Sources and hashes](sources.tsv) pin the official release archives,
verified against their upstream `.sha256sum` files on 2026-10-06.
Phoc's archive contains wlroots 0.20.2 and GVDB revision
`4758f6fb7f889e074e13df3f914328f3eecb1fd3`; their original notices remain.
The release's text-input-v3 version 2 and layer-shell compatibility patches
are applied from that archive without rewriting their headers or IDs.

Phoc and its tests use GPL-3.0-or-later; gmobile library code uses
LGPL-2.1-or-later and its tests retain their original GPL notices.
wlroots uses MIT. Corresponding upstream texts are retained in
[LICENSES](LICENSES/). Each extracted source tree retains its full original
license and copyright files.
