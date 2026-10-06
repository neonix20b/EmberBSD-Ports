#!/bin/sh
# Origin: EmberBSD; AI-assisted native Phoc build probe.
set -eu
umask 022
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin:/usr/bin:/bin
export PATH
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD is required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build.sh ABSOLUTE_NEW_DIRECTORY [ARCHIVE_DIRECTORY]' >&2; exit 2; }
work=$1
archives=${2:-}
case "$work" in /*) ;; *) echo 'Build directory must be absolute.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a path without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
jobs=${JOBS:-2}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be a positive integer.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -r "$recipe/../native-pkg-config.sh" ] || { echo 'Copy the whole phosh probe directory, including native-pkg-config.sh.' >&2; exit 2; }
for tool in cc meson ninja pkg-config tar patch sha256 curl; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
python=${PYTHON:-/usr/pkg/bin/python3.13}
[ -x "$python" ] || { echo 'Upstream Meson and generators need Python.' >&2; exit 2; }
mkdir "$work"
mkdir "$work/archives" "$work/src" "$work/logs" "$work/bin"
prefix=$work/prefix
ln -s "$python" "$work/bin/python3"
cp "$recipe/../native-pkg-config.sh" "$work/bin/pkg-config"
chmod +x "$work/bin/pkg-config"
PKG_CONFIG="$work/bin/pkg-config"
PATH="$work/bin:$PATH"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
CFLAGS='-O2 -I/usr/pkg/include -I/usr/X11R7/include -D_NETBSD_SOURCE'
LDFLAGS="-L$prefix/lib -Wl,-rpath,$prefix/lib -L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib"
export PATH PKG_CONFIG PKG_CONFIG_PATH LD_LIBRARY_PATH CFLAGS LDFLAGS
run()
{
    label=$1
    shift
    printf '%s\n' "$label"
    status=0
    "$@" > "$work/logs/$label.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        tail -80 "$work/logs/$label.log" >&2
        printf 'Stage %s failed (%s); logs: %s/logs\n' "$label" "$status" "$work" >&2
        exit "$status"
    fi
}
{
    uname -a
    cc --version
    meson --version
    pkg_info
} > "$work/logs/environment.txt" 2>&1
while read -r name expected url; do
    if [ -n "$archives" ]; then
        cp "$archives/$name" "$work/archives/$name"
    else
        curl -fLsS --connect-timeout 20 --max-time 300 "$url" -o "$work/archives/$name"
    fi
    actual=$(sha256 -q "$work/archives/$name")
    [ "$actual" = "$expected" ] || { echo "SHA256 mismatch: $name" >&2; exit 2; }
    printf '%s  %s  %s\n' "$actual" "$name" "$url" >> "$work/logs/sources.txt"
    tar -xf "$work/archives/$name" -C "$work/src"
done < "$recipe/sources.tsv"
gmobile=$work/src/gmobile-0.7.4
phoc=$work/src/phoc-0.58.0
wlroots=$phoc/subprojects/wlroots-0.20.x
for name in gmobile-wakeup-unsupported gmobile-device-tree-test; do
    run "$name-patch" patch -d "$gmobile" -p1 < "$recipe/patches/$name.patch"
done
run phoc-portability-patch patch -d "$phoc" -p1 < "$recipe/patches/phoc-portability.patch"
run phoc-test-portability-patch patch -d "$phoc" -p1 < "$recipe/patches/phoc-test-portability.patch"
# Preserve and apply exactly the release's own wlroots compatibility series.
for p in "$phoc"/subprojects/packagefiles/wlroots/text-input-v2/*.patch \
    "$phoc"/subprojects/packagefiles/wlroots/0001-Revert-layer-shell-error-on-0-dimension-without-anch.patch; do
    run "wlroots-$(basename "$p")" patch -d "$wlroots" -p1 < "$p"
done
run wlroots-x11-atoms-patch patch -d "$wlroots" -p1 < "$recipe/patches/wlroots-x11-atoms.patch"
run gmobile-setup meson setup "$work/gmobile-build" "$gmobile" \
    --prefix="$prefix" --libdir=lib --wrap-mode=nodownload \
    -Dexamples=false -Dintrospection=false -Dvapi=false -Dgtk_doc=false -Dtests=true
run gmobile-build meson compile -C "$work/gmobile-build" -j "$jobs"
run gmobile-test meson test -C "$work/gmobile-build" --no-rebuild --print-errorlogs
run gmobile-install meson install -C "$work/gmobile-build" --no-rebuild
run wlroots-setup meson setup "$work/wlroots-build" "$wlroots" \
    --prefix="$prefix" --libdir=lib --wrap-mode=nodownload \
    -Dbackends=drm,libinput,x11 -Drenderers=[] -Dallocators=[] \
    -Dsession=enabled -Dxwayland=disabled -Dexamples=false
run wlroots-build meson compile -C "$work/wlroots-build" -j "$jobs"
run wlroots-install meson install -C "$work/wlroots-build" --no-rebuild
run phoc-setup meson setup "$work/phoc-build" "$phoc" \
    --prefix="$prefix" --libdir=lib --wrap-mode=nodownload \
    -Dembed-wlroots=disabled -Dxwayland=disabled -Dtests=true
run phoc-build meson compile -C "$work/phoc-build" -j "$jobs"
run phoc-install meson install -C "$work/phoc-build" --no-rebuild
run phoc-linkage ldd "$prefix/bin/phoc"
if grep -F 'libintl.so.8' "$work/logs/phoc-linkage.log" >/dev/null; then
    echo 'Unexpected pkgsrc gettext ABI; inspect logs/phoc-linkage.log.' >&2
    exit 1
fi
cp "$recipe/nested.ini" "$work/nested.ini"
printf 'Installed privately at %s. Run test.sh for protocol tests.\n' "$prefix"
