#!/bin/sh
# Build real GTK/GLib client libraries in an isolated prefix for nested Phosh.
set -eu
umask 077
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/bin
LANG=C.UTF-8
export PATH LANG
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD build required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build-support.sh NEW_WORK_DIRECTORY [ARCHIVE_DIRECTORY]' >&2; exit 2; }
work=$1
archives=${2:-}
case "$work" in /*) ;; *) echo 'Use an absolute work directory.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a work path without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
jobs=${JOBS:-2}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be a positive integer.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
for tool in cc meson ninja tar patch sha256 pkg-config glib-mkenums gdbus-codegen; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
python=${PYTHON:-/usr/pkg/bin/python3.13}
[ -x "$python" ] || { echo 'Set PYTHON to the absolute upstream Python 3 interpreter path.' >&2; exit 2; }
case "$python" in /*) ;; *) echo 'PYTHON must be absolute.' >&2; exit 2 ;; esac
mkdir "$work"
mkdir "$work/tools" "$work/src" "$work/archives" "$work/logs"
prefix=$work/install
ln -s "$python" "$work/tools/python3"
cp "$recipe/native-pkg-config.sh" "$work/tools/pkg-config"
chmod 755 "$work/tools/pkg-config"
PATH="$work/tools:$PATH"
PKG_CONFIG="$work/tools/pkg-config"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
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
while read -r name expected url; do
    if [ -n "$archives" ]; then
        cp "$archives/$name" "$work/archives/$name"
    else
        curl -fLsS --connect-timeout 20 --max-time 300 "$url" -o "$work/archives/$name"
    fi
    actual=$(sha256 -q "$work/archives/$name")
    [ "$actual" = "$expected" ] || { echo "SHA256 mismatch: $name" >&2; exit 2; }
    printf '%s %s %s\n' "$name" "$actual" "$url" >> "$work/logs/sources.txt"
    tar -xf "$work/archives/$name" -C "$work/src"
done < "$recipe/support-sources.tsv"
for p in "$recipe/gtk3/patches/"*; do
    run "gtk3-$(basename "$p")" patch -d "$work/src/gtk-3.24.52" -p0 < "$p"
done
run feedback-patch patch -d "$work/src/feedbackd-0.7.0" -p1 < "$recipe/feedback/client-tests.patch"
run callaudio-patch patch -d "$work/src/callaudiod-0.1.99" -p1 < "$recipe/callaudio/client-only.patch"

run gtk3-setup meson setup "$work/gtk3-build" "$work/src/gtk-3.24.52" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dx11_backend=true -Dwayland_backend=true -Dquartz_backend=false -Dwin32_backend=false \
    -Dintrospection=false -Dgtk_doc=false -Dman=false -Dtests=false -Dexamples=false \
    -Ddemos=true -Dprint_backends=file,lpr,test
run gtk3-build meson compile -C "$work/gtk3-build" -j "$jobs"
run gtk3-install meson install -C "$work/gtk3-build" --no-rebuild

run bluetooth-setup meson setup "$work/bluetooth-build" "$work/src/gnome-bluetooth-46.2" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dsendto=false -Dgtk_doc=false -Dintrospection=false
run bluetooth-build meson compile -C "$work/bluetooth-build" -j "$jobs"
run bluetooth-test meson test -C "$work/bluetooth-build" --no-rebuild --print-errorlogs
run bluetooth-install meson install -C "$work/bluetooth-build" --no-rebuild

run feedback-setup meson setup "$work/feedback-build" "$work/src/feedbackd-0.7.0" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Ddaemon=false -Dudev=false -Dtests=true -Dintrospection=disabled -Dvapi=false -Dgtk_doc=false -Dman=false
run feedback-build meson compile -C "$work/feedback-build" -j "$jobs"
run feedback-test meson test -C "$work/feedback-build" --no-rebuild --print-errorlogs
run feedback-install meson install -C "$work/feedback-build" --no-rebuild

run callaudio-setup meson setup "$work/callaudio-build" "$work/src/callaudiod-0.1.99" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Ddaemon=false -Dgtk_doc=false
run callaudio-build meson compile -C "$work/callaudio-build" -j "$jobs"
run callaudio-install meson install -C "$work/callaudio-build" --no-rebuild

run versions pkg-config --modversion gtk+-wayland-3.0 gnome-bluetooth-3.0 libfeedback-0.0 libcallaudio-0.1
run gtk3-abi ldd "$prefix/lib/libgtk-3.so"
if grep -q 'libintl.so.8' "$work/logs/gtk3-abi.log"; then
    echo 'Conflicting gettext ABI detected.' >&2
    exit 1
fi
printf 'Support libraries built: %s\nGTK runtime and the Phosh shell still require a compositor.\n' "$prefix"
