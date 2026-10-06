# Optional GNOME keybindings

Apply `phosh-optional-keybindings.patch` after the three platform,
network-control and portable-build patches. It targets the same verified
Phosh 0.58.0 source described in [README.md](README.md).

The initial native Phosh startup reached shell initialization and aborted
because the installed GNOME Shell 40 keybinding schema lacked
`screen-brightness-up`. Checking the library version cannot detect this:
the separate `gsettings-desktop-schemas` build dependency was 50.1.

The shared `PHOSH_UTIL_BUILD_KEYBINDING` helper now checks the schema
attached to the actual `GSettings` object before reading a key. An absent
key produces a warning containing its schema ID and key name. That
binding contributes no action; existing bindings retain their configured
values and callbacks. No replacement accelerators or aliases are added.
The settings schemas themselves remain required dependencies.

The source audit found these callers of the shared helper:

- Brightness: `screen-brightness-up`, `screen-brightness-down`,
  `screen-brightness-up-monitor`, `screen-brightness-down-monitor`.
- Home: `toggle-overview`, `toggle-application-view`.
- Top panel: `toggle-message-tray`.
- Screenshot manager: `screenshot`.
- Run-command manager: `panel-run-dialog` in the desktop WM schema.

The screen saver uses its own existing power-button action and does not
read a configurable keybinding. Other newer settings were checked in the
native runtime: `accent-color`, `color-scheme` and `picture-uri-dark` were
present. Their behavior remains unchanged.

## Focused regression checks

Run with the same `PATH`, `PKG_CONFIG_PATH` and library search paths as the
native Phosh build:

```sh
sh test-keybindings.sh /path/to/patched/phosh-0.58.0
sh test-native-components.sh /path/to/patched/phosh-0.58.0 /path/to/build
```

The keybinding test uses the actual patched header and a temporary schema
with a memory settings backend. It checks existing configured values,
the warning and continued registration after a missing key, and an empty
binding list. It requires GTK/GIO development headers and
`glib-compile-schemas`, but no display or user settings changes.

The component helper runs the backlight and shared-memory tests from the
third patch without the full upstream test suite. It links the actual
native backlight object with a test-only zero-debug-flags getter matching
the upstream test stub. It recompiles the complete `util.c` with the
native generated configuration and uses linker section garbage collection
to isolate the real shared-memory code. It requires `-Dlogind=disabled`
and a GNU-compatible linker supporting `--gc-sections`. It does not edit
the source tree or build directory and preserves compiler/test failures.

On 2026-10-06 all three keybinding cases passed natively on EmberBSD
NetBSD 11/aarch64 against the actual patched header. The missing-key
regression had also reproduced the original abort without the patch.
The native component helper passed both backlight cases and both POSIX
shared-memory cases. The full upstream Phosh Meson suite was not run.

After the fix, the installed native shell displayed its home/app grid
and accepted keyboard search. Gedit launched from the private shell
session; text entry, saving and file contents were verified. The tested
session restart left the existing GNOME desktop running. These results
do not validate unavailable system services, hardware controls or audio;
see the [platform validation limits](README.md#native-validation-and-limits).

The patch and test helpers are local AI-assisted adaptations, licensed
GPL-3.0-or-later, and have not been submitted upstream.
