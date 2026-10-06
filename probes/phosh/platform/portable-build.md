# Portable Phosh build fixes

Apply `phosh-portable-build.patch` after `phosh-optional-platform.patch`
and `phosh-optional-networkmanager.patch` to the same verified Phosh
0.58.0 tree. Source provenance and the archive hash are in [README.md](README.md).
These local, AI-assisted adaptations have not been submitted upstream.
Upstream notices remain unchanged; the added test is GPL-3.0-or-later.

The patch addresses four concrete native compilation failures:

- `gnome-desktop` 41 lacks `gnome-desktop-version.h`. Meson now records
  the major component of the actual `gnome-desktop-3.0` dependency version
  as `PHOSH_GNOME_DESKTOP_MAJOR_VERSION`. The `ShellVersion` compatibility
  string therefore remains `41 (phosh 0.58.0)` with that dependency.
  This does not claim that GNOME Shell is installed or running.
- NetBSD does not provide the GNU `exp10` interface. The backlight now
  uses `pow(10.0, brightness)`. It remains the inverse of the existing
  `log10(level)` mapping. Rounding, clamping and the backend's already
  nonlinear scale are unchanged. The existing math library dependency
  supplies `pow`, `log10` and `round`.
- NetBSD rejects the GNU printf `%m` extension in `g_error`. The Wayland
  display diagnostic now uses `%s` with `g_strerror(errno)` and includes
  `<errno.h>`. It preserves the failure path. The `%m` month directive in
  the screenshot timestamp format is unrelated and remains unchanged.
- NetBSD 11 provides `memfd_create`, but the selected upstream backend
  includes Linux headers and uses Linux-specific sealing flags. Meson
  now enables that backend only on Linux. NetBSD uses the existing POSIX
  `shm_open` backend: exclusive creation with mode 0600, close-on-exec,
  immediate `shm_unlink`, and `ftruncate` to the requested size. It supplies
  real shared mappings for Wayland buffers without Linux sealing. Failed
  unlink or resize returns an error, closes the descriptor and preserves
  `errno`. This choice does not claim that NetBSD lacks native `memfd`.

## Regression checks

The new `backlight` unit test exercises the real `PhoshBacklight` class
with a test-only asynchronous backend. It checks hardware levels
1, 10, 100, 1000 and 10000 across a logarithmic range, fractional-exponent
rounding to level 18, the reverse mapping from a backend update, and
the unchanged nonlinear-backend branch. It uses no display or hardware.

Both backlight tests and both shared-memory tests passed natively on
EmberBSD NetBSD 11/aarch64 on 2026-10-06, using the focused helper:

```sh
sh test-native-components.sh /path/to/patched/phosh-0.58.0 /path/to/build
```

The helper links the actual native backlight object with a test-only
debug-flags getter. It recompiles the complete `util.c` with the native
generated configuration and isolates its real shared-memory functions
through linker section garbage collection. It does not run the full
upstream Phosh Meson test suite.

The tests are also registered for a normal upstream test build with
`-Dtests=true`. This separate Meson invocation was not run:

```sh
meson test -C build backlight shm --print-errorlogs
```

The new `shm` test checks the actual descriptor's close-on-exec flag,
allocation size, initially zero-filled data, visibility between two
shared mappings, mapping validity after closing the descriptor, and
`EINVAL` for a negative size. A backend may round allocation up to a page.

Inspect `build/phosh-config.h` alongside
`pkg-config --modversion gnome-desktop-3.0` to confirm that the generated
major version matches the selected build dependency. A clean native
compile with format and implicit-function-declaration errors enabled
checks the unavailable-header, printf and math-library failures directly.

The patch series applied cleanly to the pinned archive. A fresh complete
Phosh build and installation then passed on NetBSD 11/aarch64. With the
additional keybinding fix, the nested shell displayed its home/app grid
and launched Gedit; text entry and saving were verified. The conversion
test does not establish real hardware backlight control. The enabled
Linux profile and full upstream test suite were not tested.
