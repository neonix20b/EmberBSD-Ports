#!/bin/sh
# Run a private Phosh session inside an existing X11 desktop.
set -eu
umask 077
[ "$#" -ge 1 ] && [ "$#" -le 3 ] || {
    echo 'Usage: sh run-nested.sh SHELL_BUILD_DIRECTORY [OSK_PREFIX [GTK4_PREFIX]]' >&2
    exit 2
}
[ "$(id -u)" -ne 0 ] || { echo 'Run as the desktop user.' >&2; exit 2; }
: "${DISPLAY:?Run from an existing X11 desktop with DISPLAY and X authority}"
work=$1
osk=${2:-}
gtk4=${3:-}
check_path()
{
    case "$1" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*) echo 'Use paths without shell metacharacters.' >&2; exit 2 ;; esac
}
check_path "$work"
support=$(cat "$work/support-prefix.txt")
phoc=$(cat "$work/phoc-prefix.txt")
check_path "$support"
check_path "$phoc"
[ -z "$osk" ] || check_path "$osk"
[ -z "$gtk4" ] || check_path "$gtk4"
shell=$work/install
[ -x "$shell/libexec/phosh" ] && [ -x "$phoc/bin/phoc" ] || exit 2
[ -z "$osk" ] || [ -x "$osk/bin/phosh-osk-stevia" ] || {
    echo 'OSK prefix does not contain bin/phosh-osk-stevia.' >&2; exit 2
}
[ -z "$gtk4" ] || [ -x "$gtk4/bin/gtk4-demo" ] || {
    echo 'GTK4 prefix does not contain bin/gtk4-demo.' >&2; exit 2
}
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
for prefix in "$osk" "$gtk4"; do
    [ -n "$prefix" ] || continue
    PATH="$prefix/bin:$PATH"
    XDG_DATA_DIRS="$prefix/share:$XDG_DATA_DIRS"
    LD_LIBRARY_PATH="$prefix/lib:$LD_LIBRARY_PATH"
done
PHOSH_OSK_PREFIX=$osk
GSETTINGS_BACKEND=keyfile
WLR_BACKENDS=x11
WLR_RENDERER=pixman
export XDG_RUNTIME_DIR XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_DATA_DIRS
export LD_LIBRARY_PATH GSETTINGS_BACKEND WLR_BACKENDS WLR_RENDERER PHOSH_OSK_PREFIX
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
export GDK_BACKEND=wayland GDK_GL=disable GSK_RENDERER=cairo QT_QPA_PLATFORM=wayland GTK_IM_MODULE=wayland
export XDG_CURRENT_DESKTOP=Phosh:GNOME XDG_SESSION_DESKTOP=phosh XDG_SESSION_TYPE=wayland
printf '%s\n' "$DBUS_SESSION_BUS_ADDRESS" > "$XDG_RUNTIME_DIR/bus-address"
# D-Bus-activated apps must inherit the child Wayland display too. The bus
# was started before Phoc, while DISPLAY still pointed to the host X11.
dbus-update-activation-environment DISPLAY WAYLAND_DISPLAY GDK_BACKEND GDK_GL \
    GSK_RENDERER QT_QPA_PLATFORM GTK_IM_MODULE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.shell.keybindings toggle-overview "['<Control><Shift>F9']"
gsettings set org.gnome.shell.keybindings toggle-application-view "['<Control><Shift>F10']"
gsettings set org.gnome.desktop.background picture-uri ''
gsettings set org.gnome.desktop.background picture-uri-dark ''
if [ -z "$PHOSH_OSK_PREFIX" ]; then
    exec phosh -U
fi
gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true
# The X11 parent always supplies a hardware keyboard to this nested demo.
gsettings set mobi.phosh.osk ignore-hw-keyboards true
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'ru')]"
shell_pid=
osk_pid=
cleanup()
{
    trap - EXIT HUP INT TERM
    for pid in "$osk_pid" "$shell_pid"; do
        [ -n "$pid" ] || continue
        kill "$pid" 2>/dev/null || true
    done
    i=0
    while :; do
        alive=false
        for pid in "$osk_pid" "$shell_pid"; do
            [ -n "$pid" ] || continue
            if kill -0 "$pid" 2>/dev/null; then alive=true; fi
        done
        [ "$alive" = true ] || break
        i=$((i + 1))
        [ "$i" -lt 5 ] || break
        sleep 1
    done
    for pid in "$osk_pid" "$shell_pid"; do
        [ -n "$pid" ] || continue
        if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null || true; fi
        wait "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
phosh -U &
shell_pid=$!
"$PHOSH_OSK_PREFIX/bin/phosh-osk-stevia" &
osk_pid=$!
gdbus wait --session --timeout 15 sm.puri.OSK0 || {
    echo 'The on-screen keyboard did not register its D-Bus service.' >&2
    exit 1
}
status=0
# POSIX sh has no wait -n. Check both children so an OSK failure is not
# hidden until the user eventually exits the shell.
while kill -0 "$shell_pid" 2>/dev/null; do
    if ! kill -0 "$osk_pid" 2>/dev/null; then
        wait "$osk_pid" || status=$?
        osk_pid=
        [ "$status" -ne 0 ] || status=1
        echo "The on-screen keyboard exited unexpectedly ($status)." >&2
        exit "$status"
    fi
    sleep 1
done
wait "$shell_pid" || status=$?
shell_pid=
exit "$status"
SHELL
chmod 700 "$session/shell.sh"
printf '%s\n' "$session" > "$work/last-session.txt"
printf 'Nested session: %s\nPress Ctrl-C in this terminal to end it. Closing only the window may leave the session running.\n' "$session"
exec dbus-run-session -- "$phoc/bin/phoc" --config "$session/phoc.ini" \
    --socket emberbsd-phosh --no-xwayland --verbose --exec "$session/shell.sh"
