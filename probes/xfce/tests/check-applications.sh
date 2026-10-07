#!/bin/sh
# Exercise real file-manager, editor and panel interactions in an owned session.
set -eu
[ "$#" = 3 ] || { echo 'Usage: check-applications.sh PREFIX RESULT SESSION' >&2; exit 2; }
prefix=$1
result=$2
session=$3
: "${DISPLAY:?Use the isolated test display}"
: "${DBUS_SESSION_BUS_ADDRESS:?Use the private session bus}"
[ "$DISPLAY" = "$(cat "$session/display")" ]
[ "$DBUS_SESSION_BUS_ADDRESS" = "$(cat "$session/runtime/bus-address")" ]
[ "${XDG_CONFIG_HOME:-}" = "$session/config" ]
[ "${XDG_CACHE_HOME:-}" = "$session/cache" ]
[ "${XDG_DATA_HOME:-}" = "$session/data" ]
[ "${XDG_RUNTIME_DIR:-}" = "$session/runtime" ]
XDG_CONFIG_DIRS=$prefix/etc/xdg
DBUS_SYSTEM_BUS_ADDRESS=unix:path=$session/runtime/no-system-bus
LC_ALL=C
GDK_BACKEND=x11
export XDG_CONFIG_DIRS DBUS_SYSTEM_BUS_ADDRESS LC_ALL GDK_BACKEND
unset XDG_SEAT_PATH XDG_SESSION_PATH SESSION_MANAGER WAYLAND_DISPLAY WAYLAND_SOCKET
recipe=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
sh "$recipe/tests/check-session-profile.sh" "$session/config"
[ "$(xfconf-query -c xfce4-session -p /general/LockCommand)" = /usr/bin/false ]
[ "$(xfconf-query -c xfce4-session -p /shutdown/LockScreen)" = true ]
[ "$(xfconf-query -c xfce4-session -p /general/SaveOnExit)" = false ]
input()
{
    timeout --foreground -k 1 15 "$result/x11-input" "$@"
}
files=$result/xfce-files
mkdir "$files" "$files/documents"
: > "$files/note.txt"
editor_title="$files/note.txt - Mousepad"
env EMBERBSD_X11_SESSION="$session" thunar "$files" > "$result/thunar.log" 2>&1 &
input 'xfce-files - Thunar' key Control_L l
input 'xfce-files - Thunar' text "$files/documents"
input 'xfce-files - Thunar' key Return
input 'documents - Thunar' key Alt_L Left
input 'xfce-files - Thunar' key Escape
printf 'PASS: Thunar opened the test directory, navigated into documents and returned\n'

env EMBERBSD_X11_SESSION="$session" mousepad --disable-server "$files/note.txt" > "$result/mousepad-first.log" 2>&1 &
editor=$!
input "$editor_title" text 'EmberBSD Xfce saved through Mousepad'
input "*$editor_title" key Return
input "*$editor_title" key Control_L s
input "$editor_title" key Control_L q
count=0
while kill -0 "$editor" 2>/dev/null; do
    count=$((count + 1))
    [ "$count" -lt 15 ] || { echo 'Mousepad did not exit.' >&2; exit 1; }
    sleep 1
done
wait "$editor"
printf 'EmberBSD Xfce saved through Mousepad\n' > "$result/mousepad-expected.txt"
cmp "$files/note.txt" "$result/mousepad-expected.txt"
env EMBERBSD_X11_SESSION="$session" mousepad --disable-server "$files/note.txt" > "$result/mousepad-reopen.log" 2>&1 &
input "$editor_title" key Control_L End
input "$editor_title" text 'Reopened and edited again'
input "*$editor_title" key Return
input "*$editor_title" key Control_L s
input "$editor_title" key Escape
printf 'Reopened and edited again\n' >> "$result/mousepad-expected.txt"
cmp "$files/note.txt" "$result/mousepad-expected.txt"
printf 'PASS: Mousepad saved exact text, exited, reopened it and saved a second edit\n'

xfce4-panel --plugin-event=applicationsmenu:popup:bool:false > "$result/panel-menu.log" 2>&1
count=0
menu=
while [ -z "$menu" ]; do
    xwininfo -root -tree > "$result/menu-windows.txt"
    for id in $(awk '/("xfce4-panel" "Xfce4-panel")/ { print $1 }' "$result/menu-windows.txt"); do
        xwininfo -id "$id" > "$result/menu-candidate.txt"
        if grep -q 'Map State: IsViewable' "$result/menu-candidate.txt" &&
           grep -q 'Override Redirect State: yes' "$result/menu-candidate.txt"; then
            menu=$id
            cp "$result/menu-candidate.txt" "$result/menu-visible.txt"
            break
        fi
    done
    count=$((count + 1))
    [ "$count" -lt 10 ] || { echo 'Panel menu was not visible.' >&2; exit 1; }
    [ -n "$menu" ] || sleep 1
done
input --current key Escape
count=0
while xwininfo -id "$menu" 2>/dev/null | grep -q 'Map State: IsViewable'; do
    count=$((count + 1))
    [ "$count" -lt 10 ] || { echo 'Panel menu did not close.' >&2; exit 1; }
    sleep 1
done
printf 'PASS: panel application menu appeared and closed through keyboard input\n'
xfce4-panel --plugin-event=applicationsmenu:popup:bool:false >> "$result/panel-menu.log" 2>&1
count=0
until xwininfo -id "$menu" 2>/dev/null | grep -q 'Map State: IsViewable'; do
    count=$((count + 1))
    [ "$count" -lt 10 ] || { echo 'Panel menu did not reopen.' >&2; exit 1; }
    sleep 1
done
# The pinned upstream menu puts xfce4-run.desktop first. Observe the
# application and its output, not merely successful injection of a key.
input --current key Home
input --current key Return
input 'Application Finder' text 'xterm -T EmberBSD-menu'
input 'Application Finder' key Return
input EmberBSD-menu text "printf 'menu launch works\\n' > $result/menu.txt"
input EmberBSD-menu key Return
count=0
while [ ! -s "$result/menu.txt" ]; do
    count=$((count + 1))
    [ "$count" -lt 10 ] || { echo 'Menu-launched terminal did not write its file.' >&2; exit 1; }
    sleep 1
done
printf 'menu launch works\n' > "$result/menu-expected.txt"
cmp "$result/menu.txt" "$result/menu-expected.txt"
input EmberBSD-menu text exit
input EmberBSD-menu key Return
printf 'PASS: menu keyboard selection opened Application Finder and launched a working terminal\n'
