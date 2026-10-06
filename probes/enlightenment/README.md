# Enlightenment on EmberBSD

This native build probe runs Enlightenment 0.27.1 with EFL 1.28.1 and the
operating system's Lua 5.4.6. The validated target is NetBSD 11/aarch64 in
UTM, using a private X11 server and software rendering. It is a candidate
for an embedded desktop, not a validated phone shell or installable package.

The [source manifests](efl-source.tsv), [shell manifest](shell-source.tsv)
and [provenance](PROVENANCE.md) pin original upstream releases and describe
the NetBSD backports and local patches. Source archives and build products
stay outside Git.

## Dependencies and build

Use a NetBSD/EmberBSD environment with the base development and X11 sets.
The probe uses native GCC, Lua headers/library and X11 from `/usr/X11R7`.
The tested pkgsrc tools are Meson 1.11.1, Ninja 1.13.2, pkg-config and curl.
Upstream Meson and EFL generators require Python 3; the default executable
is `/usr/pkg/bin/python3.13`, overridable with `PYTHON` for the EFL build.
Project-owned helpers use shell and C.

Required development dependencies include D-Bus, GLib, Check, libsndfile,
PulseAudio, freetype/fontconfig/harfbuzz, fribidi, pixman, libxkbcommon,
xcb-util-keysyms, OpenSSL, zlib, lz4, libjpeg-turbo, PNG, TIFF, giflib,
libwebp, librsvg, libexif, desktop-file-utils and hicolor-icon-theme.
Their headers and pkg-config files must be available under `/usr/pkg` or
the base system. This probe was checked in an existing graphical build VM;
a minimal clean-machine dependency installation has not been validated.

Run as an ordinary user. Work paths must be absolute, new, and contain
only letters, digits, `_`, `.`, `/` and `-`. Parents must already exist.
The scripts reject an existing work directory and stop on failed stages.

```sh
mkdir -p "$HOME/.cache"
sh build-efl.sh "$HOME/.cache/emberbsd-efl"
sh build-shell.sh "$HOME/.cache/emberbsd-enlightenment" \
    "$HOME/.cache/emberbsd-efl/install"
```

Each builder optionally accepts its already-downloaded upstream archive
as the final argument; its checksum is still mandatory. `JOBS=2` is the
default. Logs, patched sources, build trees and installation prefixes are
retained in the selected work directories.

The EFL builder checks the native Lua ABI, Edje numeric conversions,
Lua filters and compiled theme rendering, then runs the selected upstream
Eina, Eet and Eolian suites. The shell builder checks actual-source system
policy and failed-exec status before building. The pkg-config wrapper
preserves native gettext linkage in this NetBSD package environment.

This is one EFL source and one system Lua runtime. The Lua 5.4 patch adapts
removed APIs, integer conversions and string formatting; optional Elua
and generated Lua bindings are rejected for Lua >=5.3. It does not install
an older Lua beside the system version. Experimental prefixes make the
probe removable without replacing the active desktop; they are not a
policy of maintaining separate library versions per application.

## Launch and verify

From an X11 desktop with Xephyr installed:

```sh
sh run-nested.sh "$HOME/.cache/emberbsd-enlightenment"
```

For an independent off-screen server with Xvfb installed:

```sh
sh run-nested.sh "$HOME/.cache/emberbsd-enlightenment" --headless
```

`--headless` starts a real X11 desktop but does not display it locally.
An authenticated VNC server bound to loopback can present that display
through an SSH tunnel. The probe does not install or configure VNC.
`ENLIGHTENMENT_DISPLAY_NUMBER` selects a free display, default 78.
Existing X sockets, X lock files and probe locks are rejected.

The launcher's output identifies its session directory. Each run gets
its own HOME, XDG directories, D-Bus session, X server and stock-derived
Enlightenment profile. `last-session.txt` is only a convenience pointer;
a controller should read the specific launcher's output instead.
Stop the foreground launcher with Ctrl-C, or choose Exit Enlightenment.
A normal exit returns zero. TERM and INT preserve their signal statuses.

```sh
sh test-runtime.sh "$HOME/.cache/emberbsd-enlightenment"
```

This test uses display 79 by default and a native Xlib client. It checks
WM selection ownership and identity, visible client management, actual
fullscreen/restored geometry, client removal, normal WM exit and X-server
cleanup. Blocking X requests have external deadlines. See
[process cleanup](tests/process-scope/README.md) for the separate orphan,
signal and cancellation regressions.

The launcher tags its private session's process environment. Cleanup
finds ordinary and detached applications with that exact marker, sends
TERM then KILL, and checks for remaining processes. It also owns separate
process groups for the server and D-Bus runner. Cleanup attempts are
bounded and report failures. Only stale X nodes whose lock still names
the launcher's exited server are removed. This cooperative mechanism
is not a security sandbox; an application that rewrites its environment
can escape the marker. See the helper documentation for further limits.

## Validation boundaries

Native builds, the Lua 5.4 regressions, three selected upstream EFL suites,
private-profile policy checks and the full X11 window-management contract
passed on 2026-10-06. The stock desktop, panel, menu and Everything window
were displayed through VNC. Automated keyboard forwarding through that
viewer was inconclusive; an end-to-end typed-and-saved document is not
claimed by this probe.

The private profile disables privileged helpers, setid installation,
authentication/locking, suspend, shutdown/reboot, hardware controls and
system-bus services. Exit/logout/restart of the private desktop remain
available. Those disabled operations return unsupported before changing
session state; they are not success stubs. The normal upstream build
keeps its existing system-services behavior by default.

Only X11 with software rendering is validated. Wayland, direct KMS, GPU
acceleration, physical touch input, phone layout, screen keyboard, power
management and hardware audio remain unverified. Xvfb lacks DPMS; the
logs also contain animator timing and EFL/DBus diagnostic warnings. No
whole-desktop performance or stability claim follows from this probe.

For software-composited Xvfb, the tested x11vnc viewer required
`-noxdamage -noxcomposite -nowf -noscr -fixscreen V=1` to avoid stale
window images. Keep authentication enabled and bind to loopback; use an
SSH tunnel for access. Viewer behavior is separate from the X11 contract.
