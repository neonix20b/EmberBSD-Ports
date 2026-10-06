# Openbox on EmberBSD

This probe builds Openbox 3.6.1 for native EmberBSD/NetBSD X11. Openbox
provides window placement, decoration, focus, workspaces and menus for
small graphical systems. Ports owns this source recipe and its patches.
The selected release, license and patch origins are recorded in
[PROVENANCE.md](PROVENANCE.md).

The probe installs into a new ordinary-user directory. It does not replace
the active window manager or register a system login session. Native build
and graphical runtime results must be recorded separately; preparation
and shell syntax checks alone do not establish desktop support.

## Dependencies and build

Use base development and X11 sets, plus GNU make, pkg-config, gettext
tools, GLib, Pango with Xft, libxml2, librsvg and startup-notification
development files. The compiler defaults to `/usr/bin/cc`. Existing
libraries are taken from `/usr/pkg` and `/usr/X11R7`; the probe does not
build a second dependency stack.

The reference environment has NetBSD 11/aarch64, GCC 12.5.0, GLib 2.88.1,
Pango 1.57.1, libxml2 2.15.3, librsvg 2.60.2 and startup-notification 0.12.
GNU make, `tar`, `patch`, `sha256`, `msgfmt` and `ldd` are required. Curl
is needed only when no local archive is supplied. A minimal dependency
installation has not been validated.

Run from this directory as an ordinary user:

```sh
mkdir -p "$HOME/.cache"
JOBS=1 sh build.sh "$HOME/.cache/emberbsd-openbox"
```

The work directory must be new and absolute. Its parent must exist, and
the path may contain only letters, digits, `_`, `.`, `/` and `-`. A second
argument accepts a predownloaded `openbox-3.6.1.tar.gz`; SHA256 verification
is mandatory in either case. `CC` accepts a compiler executable path;
`CFLAGS`, `CPPFLAGS` and `LDFLAGS` allow build flags. `JOBS=1` is the default.
Logs, sources and installed files remain below the work directory.

The build uses SVG image support. Optional Imlib2 file-image loading is
disabled because the reference environment does not include Imlib2.
X11 client-provided icons and the window manager's core functions remain
available. Native gettext is selected to match GLib's existing ABI;
the final executable is checked for missing libraries or `libintl.so.8`.

## Session boundary

Use the [shared isolated launcher](../x11-desktops/README.md):

```sh
sh ../x11-desktops/run-nested.sh openbox /absolute/openbox/install /absolute/openbox
sh ../x11-desktops/test-runtime.sh openbox /absolute/openbox/install /absolute/openbox
```

It starts `WORK/install/bin/openbox` on a separate X11 server with private
XDG configuration and no inherited `SESSION_MANAGER`; keep the real HOME. Give it an explicit
`--config-file` pointing to the private Openbox configuration. An isolated
launcher should supply its own terminal/application menu and stop only
the processes it started. Do not use `--replace` on the active desktop.

The upstream `openbox-session` and XDG autostart helper are preserved,
including pkgsrc's Python 3 compatibility patch. They are outside this
isolated profile. XDG autostart additionally requires Python and PyXDG;
neither is required to build or run the Openbox binary directly. The
helper's interpreter defaults to `/usr/pkg/bin/python3.13`, overridable
with `PYTHON=/absolute/path/to/python3` at build time.

Verify the running manager, map and decorate an X11 window, move/resize
and focus it, exercise the menu and workspaces, then exit the private
session. A VM result does not establish support on a physical board,
accelerated graphics, suspend, touch or a complete desktop environment.

On 2026-10-07, the native build, seven upstream unit tests and the shared
X11 runtime contract passed on NetBSD 11/AArch64 in UTM. Real xterm/vi
applications received XTEST keyboard input, saved exact text and switched
focus. Fullscreen/restored geometry and normal WM/X-server exit passed.
This does not validate physical input, touch, GPU acceleration or a phone.
