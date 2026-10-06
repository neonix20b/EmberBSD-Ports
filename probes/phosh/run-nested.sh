#!/bin/sh
# Run a private Phosh session inside an existing X11 desktop.
set -eu
umask 077
[ "$#" -eq 1 ] || { echo 'Usage: sh run-nested.sh SHELL_BUILD_DIRECTORY' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as the desktop user.' >&2; exit 2; }
: "${DISPLAY:?Run from an existing X11 desktop with DISPLAY and X authority}"
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute build directory.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a path without shell metacharacters.' >&2; exit 2 ;; esac
support=$(cat "$work/support-prefix.txt")
phoc=$(cat "$work/phoc-prefix.txt")
shell=$work/install
[ -x "$shell/libexec/phosh" ] && [ -x "$phoc/bin/phoc" ] || exit 2
PATH="$shell/libexec:$shell/bin:$support/bin:$phoc/bin:/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin:/usr/bin:/bin"
export PATH
# NetBSD sockaddr_un.sun_path has 104 bytes, including the terminator.
socket_path=$work/session.XXXXXX/runtime/emberbsd-phosh
[ "$(LC_ALL=C printf '%s' "$socket_path" | wc -c | tr -d ' ')" -le 103 ] || {
    echo 'Build path is too long for a Wayland socket; use a shorter directory.' >&2
    exit 2
}
session=$(mktemp -d "$work/session.XXXXXX")
mkdir "$session/runtime" "$session/config" "$session/cache" "$session/data"
mkdir "$session/data/applications"
cat > "$session/data/applications/emberbsd-gtk3-demo.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=GTK3 Demo
Exec=$support/bin/gtk3-demo
Icon=gtk3-demo
Terminal=false
Categories=Development;
DESKTOP
XDG_RUNTIME_DIR=$session/runtime
XDG_CONFIG_HOME=$session/config
XDG_CACHE_HOME=$session/cache
XDG_DATA_HOME=$session/data
XDG_DATA_DIRS="$shell/share:$support/share:$phoc/share:/usr/pkg/share:/usr/share"
LD_LIBRARY_PATH="$shell/lib:$support/lib:$phoc/lib:/usr/pkg/lib:/usr/X11R7/lib"
GSETTINGS_BACKEND=keyfile
WLR_BACKENDS=x11
WLR_RENDERER=pixman
export XDG_RUNTIME_DIR XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_DATA_DIRS
export LD_LIBRARY_PATH GSETTINGS_BACKEND WLR_BACKENDS WLR_RENDERER
unset WAYLAND_DISPLAY WAYLAND_SOCKET DBUS_SESSION_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE
cat > "$session/phoc.ini" <<'CONFIG'
[core]
xwayland=false

[output:X11-1]
mode=360x540
scale=1
CONFIG
cat > "$session/shell.sh" <<'SHELL'
#!/bin/sh
set -eu
DISPLAY=
export DISPLAY
export GDK_BACKEND=wayland GDK_GL=disable GSK_RENDERER=cairo QT_QPA_PLATFORM=wayland
export XDG_CURRENT_DESKTOP=Phosh:GNOME XDG_SESSION_DESKTOP=phosh XDG_SESSION_TYPE=wayland
# D-Bus-activated apps must inherit the child Wayland display too. The bus
# was started before Phoc, while DISPLAY still pointed to the host X11.
dbus-update-activation-environment DISPLAY WAYLAND_DISPLAY GDK_BACKEND GDK_GL \
    GSK_RENDERER QT_QPA_PLATFORM XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.shell.keybindings toggle-overview "['<Control><Shift>F9']"
gsettings set org.gnome.shell.keybindings toggle-application-view "['<Control><Shift>F10']"
gsettings set org.gnome.desktop.background picture-uri ''
gsettings set org.gnome.desktop.background picture-uri-dark ''
exec phosh -U
SHELL
chmod 700 "$session/shell.sh"
printf '%s\n' "$session" > "$work/last-session.txt"
printf 'Nested session: %s\nPress Ctrl-C in this terminal to end it. Closing only the window may leave the session running.\n' "$session"
exec dbus-run-session -- "$phoc/bin/phoc" --config "$session/phoc.ini" \
    --socket emberbsd-phosh --no-xwayland --verbose --exec "$session/shell.sh"
