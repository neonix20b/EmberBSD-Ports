# Xfce on EmberBSD

This source probe provides the stable Xfce 4.20 desktop: xfwm4 window
management, a panel, desktop icons, settings, session management, Thunar
file browsing and the application finder. Mousepad 0.7.0 adds a GTK3 text
editor. Ports owns the recipe; [PROVENANCE.md](PROVENANCE.md) records
versions, original source URLs and the limits of the profile.

All components install into one private prefix. The recipe preserves
the active desktop and does not register a login session. Source
preparation alone is not evidence that the desktop runs on EmberBSD.

## Requirements

Use NetBSD/EmberBSD development and X11 sets with the following existing
pkgsrc development libraries and tools:

- GTK3, GLib/GIO, Pango/Cairo, GdkPixbuf, libdisplay-info, libxklavier,
  libnotify, startup-notification, libcanberra, libexif and libpng.
- X11, Xft, Xinerama, RandR, Xcursor, XRes, XPresent, XComposite, XFixes,
  XDamage, Xrender, XI, SM and ICE from the base X11 set or shared pkgsrc.
- GNU make, Meson, Ninja, pkg-config, gettext tools, xsltproc, Perl,
  `gdbus-codegen`, GLib resource/marshalling tools, `sha256`, `tar` and
  a native C/C++ compiler. Curl is only needed without an archive cache.
- Python 3 for upstream Meson/GLib/Xfce generators. The builder uses
  `/usr/pkg/bin/python3.13` by default, overridable with `PYTHON`.
  It does not install another interpreter. No new EmberBSD helper uses Python.
- GtkSourceView 4 for Mousepad; set `BUILD_MOUSEPAD=0` to omit the editor.
  A D-Bus session bus, X11 utilities, fonts and icon themes are needed at
  runtime. A minimal clean-machine dependency installation is unverified.

The inspected NetBSD 11/aarch64 VM has GCC 12.5.0, GTK3 3.24.52,
GLib 2.88.1 and Perl 5.44.0. It lacks libwnck, libyaml and Xfce development
tools; this recipe supplies their selected source releases. Existing
matching libwnck/libyaml versions are reused; a version conflict stops
the build instead of installing a parallel copy.

No binary package operation is part of this recipe. Do not satisfy its
dependencies by downgrading the common Perl, gettext or other installed
tools. `intltool` is not required by these release configure scripts.
Meson and the small Xfce development-tools package provide the generators.

## Build

Run as an ordinary user from this directory:

```sh
mkdir -p "$HOME/.cache"
JOBS=1 sh build.sh "$HOME/.cache/emberbsd-xfce"
```

The work path must be absolute, new, have an existing writable parent,
and contain only letters, digits, `_`, `.`, `/` and `-`. A second argument
accepts a directory containing the original archives from
[sources.tsv](sources.tsv). Every archive is checked before extraction.
`CC` and `CXX` accept executable paths; `CFLAGS`, `CXXFLAGS`, `CPPFLAGS`
and `LDFLAGS` allow compiler flags. The default is `JOBS=1`.

The same recipe supports limited build windows or repeating a failed
component without rebuilding successful dependencies:

```sh
sh prepare-sources.sh "$HOME/.cache/emberbsd-xfce" /path/to/archives
JOBS=1 sh build-component.sh "$HOME/.cache/emberbsd-xfce" libwnck
JOBS=1 sh build-component.sh "$HOME/.cache/emberbsd-xfce" yaml
# Continue with component names in the first column of sources.tsv, in order.
```

`build.sh` performs both phases; do not run it on an already prepared
directory. The per-component builder can repeat a component after a
failure. Logs, sources, build directories and installs remain below the
work path. The YAML parser's upstream `make check` runs after its build.
Do not claim application support from configuration or compilation alone.

## Profile and session boundary

The profile explicitly selects X11. Wayland, Polkit integration,
libxfce4ui's optional hardware inventory, Thunar's GUdev auto-mounting,
settings' colord/UPower integration and panel DBusMenu integration are
disabled. The panel still supplies its normal application menu, task
list, pager and launchers; application-specific indicator menus need
separate validation. Introspection and Vala bindings are omitted.

xfwm4 includes its X11 compositor, but acceleration is not established.
Use a separate software-rendered X11 server for validation. The session
launcher must keep the real HOME and provide private XDG configuration,
cache, data and runtime directories,
a private D-Bus session bus, this prefix's `bin` in PATH, and
`XDG_CONFIG_DIRS=PREFIX/etc/xdg`. Put `PREFIX/share` before `/usr/pkg/share`
in `XDG_DATA_DIRS`, and put `PREFIX/lib` first in `LD_LIBRARY_PATH`.
Do not inherit `SESSION_MANAGER` or the active desktop's D-Bus address.
Use [the session policy](SESSION.md) and `prepare-session.sh` to select
supported kiosk/settings restrictions and prevent unrelated autostart.

Use `xfce4-session` inside the isolated server. Exercise its panel/menu,
Thunar, Mousepad save/reopen, window movement/focus and session exit.
Capture the running versions and actual library resolutions. Check that
no `libintl.so.8` is loaded alongside native `libintl.so.1`. Record VM
and board results separately. Hardware power control, suspend, screen
locking, touch and a display-manager login session remain outside this
profile's validation boundary.
