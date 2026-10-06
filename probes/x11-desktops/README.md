# Isolated X11 desktops

This shared launcher compares Openbox, awesomeWM, Enlightenment and Xfce
without replacing the active desktop. It uses Xephyr for a visible nested
window or Xvfb for off-screen checks. Each run owns its X server, D-Bus bus,
XDG directories and tagged applications. The real HOME is retained;
Enlightenment's supported `E_HOME` selects its private configuration.

Build the chosen [Openbox](../openbox/README.md),
[awesomeWM](../awesome/README.md), [Enlightenment](../enlightenment/README.md)
or [Xfce](../xfce/README.md) source probe first. Use an ordinary
EmberBSD/NetBSD user with the base development/X11 sets, Xephyr or Xvfb,
xterm, vi, D-Bus and the pkgsrc `timeout` command. The work directory's
parent must exist. Paths must be absolute and contain only letters,
digits, `_`, `.`, `/` and `-`.

```sh
sh run-nested.sh openbox /absolute/openbox/install /absolute/openbox
sh run-nested.sh awesome /absolute/awesome/install /absolute/awesome
EFL_PREFIX=/absolute/efl/install sh run-nested.sh enlightenment \
    /absolute/enlightenment/install /absolute/enlightenment
sh run-nested.sh xfce /absolute/xfce/install /absolute/xfce
```

Add `--headless` for Xvfb. `X11_DISPLAY_NUMBER` defaults to 82; occupied
X nodes and cooperating launcher locks are rejected. Stop the foreground
launcher with Ctrl-C or the desktop's own exit action. Private profiles
are retained under the work directory for inspection. No VNC server,
login-manager change, hardware deployment or automatic startup is installed.

## Repeatable runtime check

```sh
sh test-runtime.sh openbox /absolute/openbox/install /absolute/openbox
EFL_PREFIX=/absolute/efl/install sh test-runtime.sh enlightenment \
    /absolute/enlightenment/install /absolute/enlightenment
```

The same three arguments select awesome or xfce. The test defaults to
display 83. It verifies the WM identity and selection, a visible client,
actual fullscreen and restored geometry, and client destruction. It then
opens two real xterm applications: vi edits and saves a document, and a
shell writes a second file. XTEST keyboard events reach each application
after the WM changes input focus. Both saved byte sequences must match.
Finally, applications close through keyboard input and the desktop exits
through its own control command. The launcher must return success and
remove its X server. X11 requests have external deadlines.

The [existing lifecycle helpers](../enlightenment/tests/process-scope/README.md)
are reused with an `EMBERBSD_X11_SESSION` marker. Cleanup checks exact
process identity before signalling. The test controller has no marker and
must survive cleanup. This is cooperative process ownership, not a security
sandbox. A program that rewrites its environment can escape the marker.

## Verified scope

On 2026-10-07, Openbox 3.6.1, awesomeWM 4.3 and Enlightenment 0.27.1/EFL 1.28.1 passed
the complete test on NetBSD 11/AArch64 in UTM, using Xvfb 1024x640x24 and
software rendering. Each session exited with status zero. Openbox's seven
upstream binary-search tests also passed. The Xfce source recipe and private
profile are prepared; its native build/runtime validation remains pending.

The keyboard evidence is XTEST input into real applications. It does not
validate a physical keyboard, touchscreen, screen keyboard or VNC viewer.
There is no phone, native KMS, GPU, memory/performance or long-run stability
claim. Openbox is an intentionally small window manager, without a bundled
panel; awesome adds Lua-configured tiling and widgets; Enlightenment and
Xfce provide desktop components. These remain source probes, not a signed
binary package channel.
