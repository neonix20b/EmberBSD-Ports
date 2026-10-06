#!/bin/sh
# Build a private GTK4 prefix; never replace installed packages.
set -eu
umask 077
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin:/usr/bin:/bin
LANG=C.UTF-8
export PATH LANG
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD build required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build.sh NEW_WORK_DIRECTORY [GTK_ARCHIVE]' >&2; exit 2; }
work=$1
archive=${2:-}
case "$work" in /*) ;; *) echo 'Use an absolute work directory.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a work path without shell metacharacters.' >&2; exit 2 ;; esac
jobs=${JOBS:-2}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be a positive integer.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
for tool in cc meson ninja tar patch sha256 pkg-config curl; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
python=${PYTHON:-/usr/pkg/bin/python3.13}
case "$python" in /*) ;; *) echo 'PYTHON must be absolute.' >&2; exit 2 ;; esac
[ -x "$python" ] || { echo 'Set PYTHON to the installed upstream Python 3 interpreter.' >&2; exit 2; }
mkdir "$work"
mkdir "$work/tools" "$work/src" "$work/archives" "$work/logs"
prefix=$work/install
ln -s "$python" "$work/tools/python3"
cp "$recipe/../native-pkg-config.sh" "$work/tools/pkg-config"
chmod 755 "$work/tools/pkg-config"
PATH="$work/tools:$PATH"
PKG_CONFIG="$work/tools/pkg-config"
PKG_CONFIG_PATH="/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
CFLAGS='-O2 -I/usr/pkg/include -I/usr/X11R7/include'
LDFLAGS='-L/usr/lib -L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib'
export PATH PKG_CONFIG PKG_CONFIG_PATH LD_LIBRARY_PATH CFLAGS LDFLAGS
run()
{
    stage=$1
    shift
    printf '%s\n' "$stage"
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        tail -60 "$work/logs/$stage.log" >&2
        printf 'Stage %s failed (%s). Logs: %s/logs\n' "$stage" "$status" "$work" >&2
        exit "$status"
    fi
}
read -r name expected url < "$recipe/sources.tsv"
if [ -n "$archive" ]; then
    cp "$archive" "$work/archives/$name"
else
    curl -fLsS --connect-timeout 20 --max-time 300 "$url" -o "$work/archives/$name"
fi
actual=$(sha256 -q "$work/archives/$name")
[ "$actual" = "$expected" ] || { echo 'GTK archive checksum mismatch.' >&2; exit 2; }
printf '%s %s %s\n' "$name" "$actual" "$url" > "$work/logs/source.txt"
tar -xf "$work/archives/$name" -C "$work/src"
source=$work/src/gtk-4.22.4
run patch-build patch -d "$source" -p0 < "$recipe/patches/patch-meson.build"
run patch-seat patch -d "$source" -p0 < "$recipe/patches/patch-gdk_wayland_gdkseat-wayland.c"
run patch-shm patch -d "$source" -p1 < "$recipe/patches/wayland-shm-page-size.patch"
run shm-regression sh "$recipe/test-shm.sh" "$source" "$work/shm-test"
run setup meson setup "$work/build" "$source" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dx11-backend=true -Dwayland-backend=true -Dvulkan=disabled \
    -Dmedia-gstreamer=disabled -Dprint-cups=enabled -Dintrospection=disabled \
    -Ddocumentation=false -Dman-pages=false -Dbuild-testsuite=false \
    -Dbuild-tests=false -Dbuild-examples=false -Dbuild-demos=true
run compile meson compile -C "$work/build" -j "$jobs"
run install meson install -C "$work/build" --no-rebuild
run abi ldd "$prefix/lib/libgtk-4.so"
if grep -q 'libintl.so.8' "$work/logs/abi.log"; then
    echo 'Conflicting gettext ABI detected.' >&2
    exit 1
fi
printf 'GTK4 prefix: %s\nApplication runtime checks still require a compositor.\n' "$prefix"
