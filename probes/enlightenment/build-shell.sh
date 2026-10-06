#!/bin/sh
# Build a disposable X11 Enlightenment session against the shared EFL probe.
set -eu
umask 077
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin:/usr/bin:/bin
LANG=C.UTF-8
export PATH LANG
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD build required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo 'Usage: sh build-shell.sh NEW_WORK EFL_PREFIX [ARCHIVE]' >&2; exit 2; }
work=$1
efl=$2
for path in "$work" "$efl"; do
    case "$path" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./-]*) echo 'Use paths without shell metacharacters.' >&2; exit 2 ;; esac
done
[ -x "$efl/bin/edje_cc" ] && [ -x "$efl/bin/eet" ]
jobs=${JOBS:-2}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
for tool in cc meson ninja tar patch sha256 pkg-config curl; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
mkdir "$work"
mkdir "$work/tools" "$work/src" "$work/archives" "$work/logs"
prefix=$work/install
cp "$recipe/native-pkg-config.sh" "$work/tools/pkg-config"
chmod 755 "$work/tools/pkg-config"
PATH="$work/tools:$efl/bin:$PATH"
PKG_CONFIG="$work/tools/pkg-config"
PKG_CONFIG_PATH="$efl/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
LD_LIBRARY_PATH="$prefix/lib:$efl/lib:/usr/pkg/lib:/usr/X11R7/lib"
CFLAGS='-O2 -I/usr/pkg/include -I/usr/X11R7/include'
LDFLAGS="-L$efl/lib -Wl,-rpath,$efl/lib -L/usr/lib -L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib -lcrypt"
export PATH PKG_CONFIG PKG_CONFIG_PATH LD_LIBRARY_PATH CFLAGS LDFLAGS
printf '%s\n' "$efl" > "$work/efl-prefix.txt"
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
read -r name expected url < "$recipe/shell-source.tsv"
if [ "$#" = 3 ]; then
    cp "$3" "$work/archives/$name"
else
    curl -fLsS --connect-timeout 20 --max-time 1800 "$url" -o "$work/archives/$name"
fi
actual=$(sha256 -q "$work/archives/$name")
[ "$actual" = "$expected" ] || { echo 'Enlightenment archive checksum mismatch.' >&2; exit 2; }
printf '%s %s %s\n' "$name" "$actual" "$url" > "$work/logs/source.txt"
tar -xf "$work/archives/$name" -C "$work/src"
source=$work/src/enlightenment-0.27.1
for patchfile in "$recipe"/patches/enlightenment/patch-*; do
    run "$(basename "$patchfile")" patch -d "$source" -p0 < "$patchfile"
done
for path in src/bin/e_sys_main.c src/bin/system/e_system_main.c src/modules/conf_menus/e_int_config_menus.c; do
    sed "s|@PREFIX@|$prefix|g" "$source/$path" > "$source/$path.tmp"
    mv "$source/$path.tmp" "$source/$path"
done
run patch-private-profile patch -d "$source" -p1 < "$recipe/patches/enlightenment/private-profile.patch"
run private-profile sh "$recipe/tests/private-profile/check-private-profile.sh" "$source"
run start-status sh "$recipe/tests/test-start-status.sh" "$source"
run setup meson setup "$work/build" "$source" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dsystem-services=false -Dsystemd=false -Ddevice-udev=false \
    -Dmount-udisks=false -Dmount-eeze=false -Dbluez5=false -Delput=false \
    -Dgesture-recognition=false -Dcpufreq=false -Dtemperature=false \
    -Dwl=false -Dxwayland=false -Dpam=false -Dconnman=false \
    -Dbacklight=false -Dbattery=false -Dpolkit=false -Dgeolocation=false \
    -Dconvertible=false -Dpackagekit=false -Dlokker=false \
    -Dinstall-sysactions=false -Dinstall-system=false
run compile meson compile -C "$work/build" -j "$jobs"
run install meson install -C "$work/build" --no-rebuild
mkdir -p "$prefix/etc/xdg/menus"
cp "$prefix/share/examples/enlightenment/e-applications.menu" "$prefix/etc/xdg/menus/"
find "$prefix" -type f \( -perm -4000 -o -perm -2000 \) -print > "$work/logs/setid.txt"
[ ! -s "$work/logs/setid.txt" ] || { echo 'Unexpected setid file in private prefix.' >&2; exit 1; }
run abi ldd "$prefix/bin/enlightenment"
if grep -q 'libintl.so.8\|not found' "$work/logs/abi.log"; then
    echo 'Library resolution or gettext ABI error.' >&2
    exit 1
fi
printf 'Enlightenment prefix: %s\nRun sh %s/run-nested.sh %s from X11.\n' "$prefix" "$recipe" "$work"
