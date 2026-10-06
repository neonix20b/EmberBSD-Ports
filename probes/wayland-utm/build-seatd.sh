#!/bin/sh
# Origin: EmberBSD, AI-assisted. Build and stage seatd; never install as root.
set -eu
umask 022
PATH=/usr/pkg/bin:/usr/bin:/bin
export PATH
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD build required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build-seatd.sh ABSOLUTE_NEW_DIRECTORY [ARCHIVE_DIRECTORY]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Build directory must be absolute.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a build path without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$work"
mkdir "$work/src" "$work/log"
read -r name expected url < "$recipe/seatd-source.tsv"
if [ "$#" -eq 2 ]; then
    cp "$2/$name" "$work/$name"
else
    curl -fLsS --connect-timeout 20 --max-time 300 "$url" -o "$work/$name"
fi
[ "$(sha256 -q "$work/$name")" = "$expected" ] || { echo 'SHA256 mismatch.' >&2; exit 2; }
printf '%s  %s  %s\n' "$expected" "$name" "$url" > "$work/log/sources.txt"
tar -xf "$work/$name" -C "$work/src"
source=$work/src/seatd-0.9.3
for p in "$recipe/patches/seatd"/*; do
    patch -d "$source" -p0 < "$p"
done
sh "$recipe/tests/seatd-keyboard.sh" "$source" "$work/keyboard-test"
meson setup "$work/build" "$source" --prefix=/usr/pkg --libdir=lib \
    --buildtype=release --wrap-mode=nodownload -Dlibseat-logind=disabled \
    -Dlibseat-builtin=enabled -Dman-pages=disabled > "$work/log/setup.log" 2>&1
meson compile -C "$work/build" -j 2 > "$work/log/build.log" 2>&1
meson test -C "$work/build" --no-rebuild --print-errorlogs > "$work/log/test.log" 2>&1
DESTDIR="$work/stage" meson install -C "$work/build" --no-rebuild > "$work/log/install.log" 2>&1
printf 'Staged at %s/stage/usr/pkg. No system files or privileges changed.\n' "$work"
