# Isolated Xfce session policy

The generic X11 launcher owns server, D-Bus and process cleanup. Before
starting the session, prepare its fresh private XDG configuration:

```sh
sh prepare-session.sh "$prefix" "$XDG_CONFIG_HOME"
```

Keep the real HOME, with private `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`,
`XDG_DATA_HOME` and `XDG_RUNTIME_DIR`. Set `XDG_CONFIG_DIRS` to exactly
`$prefix/etc/xdg`; do not append `/usr/pkg/etc/xdg` or `/etc/xdg`.
Xfce reads autostart entries from the configuration search path.
Application data and menus may still use
`XDG_DATA_DIRS=$prefix/share:/usr/pkg/share:/usr/share`.

Run the session on a private D-Bus session bus. Set
`DBUS_SYSTEM_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/no-system-bus`, where
that socket does not exist. This produces a real connection failure for
system-service requests. Unset inherited `SESSION_MANAGER`,
`XDG_SEAT_PATH` and `XDG_SESSION_PATH`. Do not run `startxfce4`, which is
an X server/session startup wrapper; the nested server already exists.
Run the built `xfce4-session` directly.

## Supported configuration

`prepare-session.sh` starts from the installed upstream XML defaults.
It applies supported properties without changing session-manager code:

- The prefix's `etc/xdg/xfce4/kiosk/kioskrc` sets `Shutdown=NONE` and
  `SaveSession=NONE`. libxfce4util reads this compiled path, independently
  of `XDG_CONFIG_HOME`. Shutdown and reboot requests return an error.
- Session save-on-exit, GNOME/KDE compatibility and automatic SSH/GPG
  agents are disabled. The explicit five-client failsafe desktop remains:
  xfwm4, xfsettingsd, panel, Thunar daemon and xfdesktop.
- The panel actions plugin contains only logout. The lock keyboard
  command has an explicit empty value. Xfconf merges system defaults,
  so omitting the property would restore `xflock4`; the shortcuts provider
  ignores empty commands. Suspend, hibernate, hybrid-sleep and user
  switching are hidden from the logout dialog.
- `/general/LockCommand=/usr/bin/false` deliberately fails lock attempts.
  libxfce4ui does not try another locker after a configured command fails.
  `/shutdown/LockScreen=true` makes suspend/hibernate requests fail before
  executing a sleep backend. This is necessary because Xfce 4.20.4's
  `Shutdown` kiosk capability does not guard those sleep methods.
- xfsettingsd's autostart entry is masked because it is already an
  explicit session client. Other system autostart directories are excluded.

The failing lock command never reports a successful lock. A failed
request is an expected profile boundary, not a validated power action.
This is an ordinary-user test profile, not a security boundary against
someone editing its files or deliberately running unrelated commands.

## Verification required

Check the generated XML with `xmllint` before launching the session:

```sh
sh tests/check-session-profile.sh "$XDG_CONFIG_HOME"
```

This checks the explicit empty lock shortcut, `/usr/bin/false` lock
command and the panel's single `+logout` action. It reads the private
configuration without launching Xfce or contacting a D-Bus service.

Before using the profile, confirm the session's effective XDG paths,
`Shutdown` policy, lock command, panel action items and private bus.
Verify logout leaves the outer desktop alive. Test terminal/application
launch, Thunar file access, Mousepad save/reopen, window move/resize/focus,
workspaces and menu navigation. Do not test destructive system actions
on the host; their policy can be inspected directly from configuration
and checked against the source's rejection paths.

Source references in the pinned releases are `xfce-kiosk.c` and
`xfce-resource.c` in libxfce4util, `xfce-screensaver.c` in libxfce4ui,
`xfce-shortcuts-provider.c` in libxfce4ui's `libxfce4kbd-private`,
`xfconf-backend-perchannel-xml.c` in xfconf,
`xfsm-shutdown.c`, `xfsm-startup.c` and `xfsm-global.c` in xfce4-session,
and `plugins/actions/actions.c` in xfce4-panel.
