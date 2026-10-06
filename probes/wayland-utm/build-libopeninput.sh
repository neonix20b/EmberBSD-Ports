#!/bin/sh
# Origin: EmberBSD, AI-assisted. Private wscons input library; no system install.
set -eu
umask 022
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/bin
export PATH
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD build required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build-libopeninput.sh ABSOLUTE_NEW_DIRECTORY [ARCHIVE_DIRECTORY]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Build directory must be absolute.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a build path without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$work"
mkdir "$work/src" "$work/log"
read -r name expected url < "$recipe/libopeninput-source.tsv"
if [ "$#" -eq 2 ]; then
    cp "$2/$name" "$work/$name"
else
    curl -fLsS --connect-timeout 20 --max-time 300 "$url" -o "$work/$name"
fi
[ "$(sha256 -q "$work/$name")" = "$expected" ] || { echo 'SHA256 mismatch.' >&2; exit 2; }
printf '%s  %s  %s\n' "$expected" "$name" "$url" > "$work/log/sources.txt"
tar -xf "$work/$name" -C "$work/src"
source=$work/src/libopeninput-dcf8584ec3f5cde2a2098de25276242d2d815cc7
for p in "$recipe/patches/libopeninput"/*; do
    patch -d "$source" -p0 < "$p"
done
prefix=$work/install
PKG_CONFIG_PATH=/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig
CFLAGS='-O2 -I/usr/pkg/include -I/usr/pkg/include/libepoll-shim'
LDFLAGS='-L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -lepoll-shim'
export PKG_CONFIG_PATH CFLAGS LDFLAGS
{
    uname -a
    cc --version
    meson --version
    pkg_info
} > "$work/log/environment.txt" 2>&1
meson setup "$work/build" "$source" --prefix="$prefix" --libdir=lib \
    --buildtype=release --wrap-mode=nodownload -Dlibwacom=false \
    -Ddocumentation=false -Dtests=false -Ddebug-gui=false -Dlua-plugins=disabled \
    > "$work/log/setup.log" 2>&1
meson compile -C "$work/build" -j 2 > "$work/log/build.log" 2>&1
sh "$recipe/tests/wscons-absolute.sh" "$source" "$work/build" "$work/wscons-absolute-test" \
    > "$work/log/absolute-test.log" 2>&1
meson install -C "$work/build" --no-rebuild > "$work/log/install.log" 2>&1
printf 'Private libinput installed at %s. System packages unchanged.\n' "$prefix"
