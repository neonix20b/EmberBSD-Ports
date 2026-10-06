# Optional Phosh platform integrations

The four-patch series built and installed Phosh 0.58.0 from a fresh source
tree on EmberBSD NetBSD 11/aarch64. The nested Wayland session displayed
the home/app grid and launched an application. The platform patch
explicitly omits logind/systemd and Linux rfkill. It does not implement
NetBSD suspend, radios, brightness control or a system login session.

The separate [network-control profile](networkmanager.md) can then omit
NetworkManager-dependent Wi-Fi/VPN/WWAN controls for a nested shell.
Apply the [portable build fixes](portable-build.md) after both patches.
Then apply the [optional keybinding compatibility fix](keybindings.md)
when the installed GNOME Shell schema lacks newer bindings.

## Build options

Apply `phosh-optional-platform.patch` to the verified release tree with
`patch -p1`, then add these options to the Phosh Meson setup command:

```sh
-Dlogind=disabled -Drfkill=disabled
```

`logind` defaults to `enabled`, retaining upstream's required
`libsystemd`/`libelogind` dependency. Explicit `auto` discovers that
dependency; `disabled` skips it even when installed.

`rfkill` defaults to `auto`: it enables the existing backend only on Linux
with `linux/rfkill.h`. Explicit `enabled` fails configuration when the
platform cannot provide that backend. Neither option substitutes a
success-returning implementation for a missing system service.

The Meson summary reports both capabilities. Disabling logind also omits
the systemd user units from installation. Use a private prefix; this
directory does not provide a complete Phosh build or installation recipe.

## Behavior without the integrations

- Phosh reports disabled logind integration at startup. It does not call
  `sd_notify`, invent a system session ID, contact login1, or try to put
  launched applications into systemd scopes. Normal application launching
  and toplevel tracking remain enabled; systemd Flatpak scope tracking is
  unavailable.
- Suspend is disabled in the shell action and in the panel/power menu.
  With logind enabled, the backend action remains disabled until the
  login1 bus name has an owner, and disables again if that owner vanishes.
- The screen saver keeps its Wayland monitor notifications and local
  lock handling. System lock notifications, power-key inhibition and
  sleep inhibition are unavailable when logind is disabled.
- The udev manager returns no session proxy without an owner of the
  login1 name. Sysfs backlight construction then returns
  `G_IO_ERROR_NOT_SUPPORTED`; an asynchronous request with no proxy also
  completes with that error. Torch control remains absent.
- The hardware kill switch manager reports the disabled backend and
  leaves `mic-present` and `camera-present` false. It does not report an
  observed microphone/camera safety state or simulate a radio device.

Existing lockscreen/PAM code is preserved. A visible nested lock screen
does not establish secure system locking. GNOME SessionManager is a
separate service: this patch does not fabricate its session registration,
logout, shutdown or reboot responses.

Run the nested experiment on its own session bus with `dbus-run-session`.
Upstream Phosh owns/replaces desktop D-Bus names, including
`org.gnome.ScreenSaver`, so it must not share the active desktop's bus.
Use `-U` for the initial visual experiment and a separate settings backend
or settings directory; do not change the active desktop's lock settings.

## Native validation and limits

On 2026-10-06 the following checks passed on EmberBSD NetBSD 11/aarch64:

| Check | Result |
|---|---|
| Fresh Phosh 0.58.0 build and installation | Passed with all four patches |
| Disabled HKS backend | 1/1 tests passed against the real manager |
| Optional keybindings | 3/3 tests passed against the patched header |
| Backlight conversion | 2/2 tests passed using the native backlight object |
| POSIX shared memory | 2/2 tests passed using native `util.c` and build configuration |
| Network-free UI templates and GLib resource bundle | Passed |

The nested shell displayed its home/app grid and accepted keyboard
search. Gedit launched from the shell over its private D-Bus/Wayland
session; entered text was saved and its file contents verified. Restart
checks confirmed that terminating Phosh with SIGTERM also ended the
private Phoc and session-bus processes. The existing GNOME desktop remained running.

The HKS test requires no GTK, display server, rfkill device or system
service:

```sh
sh test-hks-unavailable.sh /path/to/patched/phosh-0.58.0
```

The helper compiles the real manager with `PHOSH_HAVE_RFKILL=0` and checks
the unavailable diagnostic and both presence properties. It requires a C
compiler, `pkg-config` and GLib/GObject headers and libraries.

The other focused checks are described in [networkmanager.md](networkmanager.md),
[portable-build.md](portable-build.md) and [keybindings.md](keybindings.md).
The full upstream Phosh Meson test suite was not run.

This validates the tested nested desktop workflow. It does not validate
secure system locking/PAM, hardware brightness, radios, suspend, or a
complete phone session. Runtime diagnostics still report unavailable
logind, Polkit/ConsoleKit session integration, GNOME SessionManager,
ambient sensing and emergency services. GVC audio criticals were observed;
audio functions were not validated.

The default GTK4 widget-factory rendering path crashed in the experiment.
The private launch environment selects `GSK_RENDERER=cairo`, but installed
GTK4 demos still fail to create Wayland shared-memory buffers. GTK4 and
GPU acceleration remain unvalidated. The enabled Linux
profile, including real logind/rfkill and service disappearance, remains
unverified. Preserve build and runtime failures when repeating the probe.

## Provenance

- Upstream: [Phosh 0.58.0 source archive](https://sources.phosh.mobi/releases/phosh/phosh-0.58.0.tar.xz).
- SHA256: `b936af34ebed15b29d4f941c48aa328a47da9c2e51cbf6ef89040a90f522ed73`.
- Source downloaded and verified on 2026-10-06. Original source archives
  and notices are unchanged. The patch preserves upstream C style and
  copyright/SPDX headers.
- Patch and regression test: local EmberBSD adaptation, AI-assisted,
  not submitted to or accepted by upstream. The changed Phosh code and
  test use GPL-3.0-or-later; see the existing
  [license text](../LICENSES/GPL-3.0-or-later.txt).
- Source working copy, archives, binaries and complete logs are outside
  this repository. Meson remains an upstream Python-based build tool.
