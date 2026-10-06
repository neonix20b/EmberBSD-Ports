#!/bin/sh
# Build upstream Openbox in an ordinary user's private prefix.
set -eu
umask 077
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin:/usr/bin:/bin
LANG=C.UTF-8
export PATH LANG
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build.sh NEW_WORK [ARCHIVE]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a path without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || { echo 'JOBS must be positive.' >&2; exit 2; }
CC=${CC:-/usr/bin/cc}
export CC
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
for tool in "$CC" gmake tar patch sha256 pkg-config msgfmt ldd; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
if [ "$#" = 1 ]; then
    command -v curl >/dev/null || { echo 'Missing tool: curl' >&2; exit 2; }
fi
mkdir "$work"
mkdir "$work/src" "$work/archives" "$work/logs" "$work/tools"
prefix=$work/install
cp "$recipe/native-pkg-config.sh" "$work/tools/pkg-config"
chmod 755 "$work/tools/pkg-config"
PKG_CONFIG="$work/tools/pkg-config"
PKG_CONFIG_PATH=/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig
LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
CFLAGS=${CFLAGS:--O2}
CPPFLAGS="${CPPFLAGS:-} -I/usr/pkg/include -I/usr/X11R7/include"
LDFLAGS="${LDFLAGS:-} -L/usr/lib -L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib"
export PKG_CONFIG PKG_CONFIG_PATH LD_LIBRARY_PATH CFLAGS CPPFLAGS LDFLAGS
run()
{
    stage=$1
    shift
    printf '%s\n' "$stage"
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        tail -60 "$work/logs/$stage.log" >&2
        printf 'Stage %s failed (%s); logs: %s/logs\n' "$stage" "$status" "$work" >&2
        exit "$status"
    fi
}
run dependencies "$PKG_CONFIG" --modversion glib-2.0 pango pangoxft libxml-2.0 \
    librsvg-2.0 libstartup-notification-1.0
read -r name expected url < "$recipe/sources.tsv"
if [ "$#" = 2 ]; then
    cp "$2" "$work/archives/$name"
else
    run download curl -fLsS --connect-timeout 20 --max-time 900 "$url" -o "$work/archives/$name"
fi
actual=$(sha256 -q "$work/archives/$name")
[ "$actual" = "$expected" ] || { echo 'Openbox archive checksum mismatch.' >&2; exit 2; }
printf '%s %s %s\n' "$name" "$actual" "$url" > "$work/logs/source.txt"
tar -xzf "$work/archives/$name" -C "$work/src"
source=$work/src/openbox-3.6.1
for patchfile in "$recipe"/patches/patch-*; do
    run "$(basename "$patchfile")" patch -d "$source" -p0 < "$patchfile"
done
# This optional upstream helper is not used by the isolated Openbox session.
# Keep its Python 3 port usable with the operating system's selected interpreter.
python=${PYTHON:-/usr/pkg/bin/python3.13}
case "$python" in /*) ;; *) echo 'PYTHON must be an absolute executable path.' >&2; exit 2 ;; esac
case "$python" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple PYTHON path.' >&2; exit 2 ;; esac
sed "1s|.*|#!$python|" "$source/data/autostart/openbox-xdg-autostart" > "$work/tools/openbox-xdg-autostart"
cp "$work/tools/openbox-xdg-autostart" "$source/data/autostart/openbox-xdg-autostart"
{
    uname -a
    "$CC" --version
    gmake --version
    printf 'CFLAGS=%s\nCPPFLAGS=%s\nLDFLAGS=%s\n' "$CFLAGS" "$CPPFLAGS" "$LDFLAGS"
} > "$work/logs/tools.txt"
cd "$source"
run configure ./configure --prefix="$prefix" --sysconfdir="$prefix/etc" \
    --libdir="$prefix/lib" --with-libintl-prefix=/usr \
    --x-includes=/usr/X11R7/include --x-libraries=/usr/X11R7/lib \
    --disable-imlib2 --enable-librsvg --enable-startup-notification
run build gmake -j "$jobs"
run install gmake install
run abi ldd "$prefix/bin/openbox"
if grep -q 'libintl.so.8\|not found' "$work/logs/abi.log"; then
    echo 'Library resolution or gettext ABI error.' >&2
    exit 1
fi
run version "$prefix/bin/openbox" --version
mkdir -p "$prefix/share/openbox/provenance"
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$prefix/share/openbox/provenance/"
cp -R "$recipe/patches" "$recipe/LICENSES" "$prefix/share/openbox/provenance/"
printf 'Openbox installed in %s. Build success does not establish an X11 runtime result.\n' "$prefix"
