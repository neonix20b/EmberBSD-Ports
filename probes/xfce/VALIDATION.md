# Native Xfce validation

On 2026-10-07, the pinned Xfce 4.20 desktop passed an actual application
workflow on NetBSD 11/AArch64 in UTM. Ports owns the source recipe and
private session profile. This is an ordinary-user source probe, not an
installable package set or a phone image.

## Build and platform

All 17 components in [sources.tsv](sources.tsv) built and installed into
one private prefix. Their original archive hashes were checked before
extraction. The build used GCC 16.2.0, one job, GTK3 3.24.52, GLib 2.88.1
and the VM's existing shared dependencies. Upstream generators still use
the installed Python 3.13. No additional legacy dependency stack was
installed. The base compiler and system library defaults were not changed.

The source selection includes panel 4.20.8, libxfce4windowing 4.20.7,
settings 4.20.5, session 4.20.4, Thunar 4.20.10 and Mousepad 0.7.0.
[Provenance](PROVENANCE.md) lists all selected releases and original sources.
The libyaml 0.2.5 upstream `make check` suite passed. Installed libwnck 43.3
passed the [native C API check](tests/check-libwnck.sh) without loader overrides.

The VM had four CPUs and 4 GiB RAM. Bounded serial builds and runtime
checks retained at least 512 MiB free plus inactive memory, 1 GiB free on
root and 2 GiB on the build volume. These are resource guards, not memory
or performance benchmarks. The runtime server was Xvfb, 1024x640x24;
no DRM, display-manager or physical-console transition was performed.

The first session installation exposed upstream's independent
`XSESSION_PREFIX=/usr` default. Installation as an ordinary user failed
at `/usr/share/xsessions`. Explicitly selecting the private prefix fixed
it; the installed `share/xsessions/xfce.desktop` was present and no system
login entry was installed. No upstream C source patch was necessary.

## Passed user workflow

The final [runtime test](../x11-desktops/test-runtime.sh) returned zero:

- Xfwm4 owned the WM selection and identified itself correctly. A real
  client entered fullscreen, changed its actual geometry, restored its
  original size and disappeared from the managed window list on exit.
- Two xterm applications received XTEST keyboard input after focus changes.
  vi saved a document and the second terminal saved a separate exact string.
- Thunar opened a test directory, navigated into its child and returned.
- Mousepad saved exact text through Ctrl+S, exited through Ctrl+Q, reopened
  the file and saved a second edit without losing the first.
- The panel application menu appeared and closed through Escape. Keyboard
  selection of its first entry opened Application Finder, which launched
  a working terminal. That terminal wrote the expected file through input.
- The private profile and effective Xfconf values retained the failing lock
  command, disabled session saving and logout-only panel action policy.
- Normal session logout returned zero and stopped the owned X server.
  The launcher confirmed cleanup of its tagged processes.

The input helper originally rejected GTK's input-only child as the focus
owner. The recorded child belonged to the requested top-level window;
checking that ancestry fixed the false failure. The test also waits for
both initial terminal windows before typing and rejects focus loss during
text injection. The final complete run passed after these changes.

## Library and validation limits

The installed C consumer enumerates actual loaded DSOs. It passed with
one libgcc_s and one libstdc++ family. Existing GTK dependencies still load
the base C++ runtime through their transitive dependency chain. A previous
diagnostic incorrectly required the GCC candidate's runtime in this C
process; that diagnostic failed even though the real C API passed.
No artificial C++ dependency, preload or global DSO replacement was added.
The [common toolchain profile](../../profiles/development-toolchain/README.md)
retains its separate C++ ABI migration acceptance checks.

`ldd` resolution for all seven principal GUI executables selected native
`libintl.so.1`; it did not select `libintl.so.8`. This resolution check is
not a trace of every dynamically loaded plugin. The desktop run uses the
private prefix with existing common GTK libraries, as described in the
[build instructions](README.md).

Physical keyboard/touch input, VNC input, a screen keyboard, GPU
acceleration, native KMS, system power actions, suspend, screen locking,
board deployment, clean-machine dependencies and long-run stability are
unverified. Thumbnail services are absent in this profile. System-bus
connection failures are expected at the explicit private-session boundary.
The public recipe and successful X11 workflow do not close these gaps.
