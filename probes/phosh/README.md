# Native Phosh on EmberBSD

**2026-10-06: Phosh 0.58.0 builds and starts natively on NetBSD 11/aarch64
inside the existing GNOME/X11 desktop.** The nested Phoc compositor uses
its X11 backend and pixman software rendering. The home screen, application
list and keyboard search are visible. Launching gedit from Phosh, typing
and saving text through its Wayland window were verified.
GTK3 Demo was launched as a second application; the overview displayed
both thumbnails and selecting the editor returned it to the foreground.

This is an experimental nested session. It does not establish a working
phone image, direct display/input drivers, GPU acceleration, modem,
Wi-Fi controls, suspend, screen locking or on-screen keyboard support.
Missing platform services are reported or their controls are excluded.
No success-returning replacement libraries are used.

## Build

Copy this entire directory to an EmberBSD/NetBSD 11 development machine.
Use an ordinary user and the installed pkgsrc GNOME environment from the
[GNOME example](https://github.com/neonix20b/EmberBSD-Examples/tree/main/desktop/gnome-utm).
Each work directory must be new, absolute and have an existing parent.
Paths must contain only letters, digits, `_`, `.`, `/` and `-`.

```sh
sh build-support.sh "$HOME/.cache/phosh-support"
sh phoc/build.sh "$HOME/.cache/phoc-native"
sh phoc/test.sh "$HOME/.cache/phoc-native"
sh build-shell.sh "$HOME/.cache/phosh-shell" \
  "$HOME/.cache/phosh-support/install" "$HOME/.cache/phoc-native/prefix"
```

See [support libraries](support.md) and [Phoc](phoc/README.md) for their
required development dependencies. The shell additionally needs
AppStream, evolution-data-server, fribidi, gcr, gnome-desktop3,
gsettings-desktop-schemas, gudev, libhandy, polkit, libsoup3, libsecret,
libupower, PAM, PulseAudio development files and `xsltproc`.
The helpers stop with the real error when a dependency is missing.
They do not install or replace system packages.

All source archives come from pinned original URLs and are SHA256 checked.
Optional final arguments accept local archives: a directory for the first
two builders, the Phosh archive file for `build-shell.sh`. Meson automatic
downloads are disabled. `JOBS` defaults to 2. Upstream Meson and code
generators use Python; our helpers use shell/C and create only a private
`python3` alias. Complete logs remain under each build directory.

The support prefix contains GTK 3.24.52 with Wayland, GNOME Bluetooth
46.2, libfeedback 0.7.0 and libcallaudio 0.1.99. Phoc 0.58.0 uses its
bundled wlroots 0.20.2 and gmobile 0.7.4. The
[native pkg-config wrapper](native-pkg-config.sh) selects the installed
GLib stack's native `libintl.so.1` and avoids mixing gettext ABIs.

## Run

From a terminal in the existing X11 desktop, with its normal `DISPLAY`
and X authority, run:

```sh
sh run-nested.sh "$HOME/.cache/phosh-shell"
```

The launcher reads the prefixes recorded by the successful shell build.
It creates a fresh private session directory, settings backend and D-Bus
session. Only Phoc sees the host X11 display; Phosh and D-Bus-activated
applications receive the nested Wayland display. GTK4 clients select the
Cairo renderer. The requested output is 360x540; GNOME on the tested
800x600 desktop constrained its usable height to 531 pixels.

Phosh starts unlocked for this visual experiment. Idle locking is disabled
only in the private settings. A solid background avoids missing host
wallpaper files. This is not a secure login session.

- `Ctrl+Shift+F9`: toggle the overview.
- `Ctrl+Shift+F10`: open the application list.
- Choose **Show All Apps** to include desktop applications. Use Tab,
  Shift+Tab and Enter, or ordinary pointer input where available.
- Press Ctrl-C in the launching terminal to end the nested session.
  Closing only its X11 window may leave the processes running.

The launcher does not alter `.xsession`, XDM or the active GNOME settings.
It keeps session files for inspection; their path is printed and recorded
in `last-session.txt`. A path exceeding NetBSD's Unix-socket limit is
rejected before launch. Xwayland is disabled; X11-only applications cannot
run inside this profile.

## Verified boundaries

Fresh builds and runtime checks used EmberBSD `EMBER64` from OS revision
`b4f718d`, NetBSD 11/aarch64, GCC 12.5.0, Meson 1.11.1 and pkgsrc
`11.0_2026Q2` dependencies on 2026-10-06.

| Check | Result |
|---|---|
| Support helper, compositor helper, shell helper | Fresh native builds completed in private prefixes |
| GNOME Bluetooth | 2 tests passed; integration test skipped |
| libfeedback | Schema validation and event test passed |
| gmobile | 7 suites passed |
| Phoc | 19 protocol/compositor tests passed using isolated Xvfb |
| Phosh local regressions | HKS 1, keybindings 3, backlight 2 and shared memory 2 passed; network UI/resource validation passed |
| Phosh desktop | Home screen, app list, keyboard search, gedit launch and text save verified |
| Repeated launch | Own shell terminated and relaunched; host GNOME remained running |

The complete upstream Phosh test suite was not run. GTK's full test suite
and physical-device functionality remain unverified. Mouse automation in
the UTM client did not reliably move the guest pointer; recorded input
checks used keyboard navigation. An on-screen keyboard is not included.

[Platform patches](platform/README.md) omit Linux logind and rfkill.
[Network profile](platform/networkmanager.md) omits NetworkManager-dependent
Wi-Fi/VPN/WWAN controls, including the dependent ModemManager path.
Applications can use the host OS's existing network. Brightness, torch,
suspend and hardware kill-switch monitoring are unavailable. Service
warnings remain for session management, Polkit/ConsoleKit, sensors and
calls. PulseAudio's GVC emits port assertions; audio behavior is unverified.
The red battery indicator does not establish actual battery integration.

Installed GTK4 Demo and Widget Factory crash in Wayland shared-memory
buffer creation. Selecting Cairo does not fix that GTK4 incompatibility.
The private profile includes a **GTK3 Demo** launcher for the tested toolkit;
the similarly named system **GTK Demo** uses GTK4 and remains unsupported.

The independent [client-library probe](client-libs/README.md) built genuine
libmm-glib 1.24.2 with two passing tests. libnm 1.54.3 did not compile.
Neither library is required by the disabled-network nested profile.

## Provenance

[Phosh 0.58.0](https://sources.phosh.mobi/releases/phosh/phosh-0.58.0.tar.xz)
SHA256: `b936af34ebed15b29d4f941c48aa328a47da9c2e51cbf6ef89040a90f522ed73`.
The build applies the four patches documented under [platform](platform/):
optional platform integrations, optional NetworkManager, portable C/build
fixes and optional keybindings for older GNOME Shell schemas.
Sources remain separate from this recipe repository.

Local adaptations and helpers are AI-assisted and have not been submitted
to or accepted by upstream. Original licenses and attribution are retained.
See the component documentation for original URLs, hashes, copied pkgsrc
patch identifiers and license texts.

The original `probe.sh` and `gmobile-device-tree-test.patch` are retained as
the earlier unmodified-Phosh dependency experiment. That probe still stops
at missing GTK3 Wayland and is not the working session recipe above. It was
moved unchanged from Examples commit `d501139` in Ports commit `809eff7`.
