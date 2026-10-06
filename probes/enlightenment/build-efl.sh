#!/bin/sh
# Build EFL for the private X11/software Enlightenment probe.
set -eu
umask 077
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin:/usr/bin:/bin
LANG=C.UTF-8
export PATH LANG
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD build required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build-efl.sh NEW_WORK [ARCHIVE]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a path without shell metacharacters.' >&2; exit 2 ;; esac
jobs=${JOBS:-2}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
python=${PYTHON:-/usr/pkg/bin/python3.13}
[ -x "$python" ] || { echo 'Set PYTHON to the upstream Python 3 interpreter.' >&2; exit 2; }
for tool in cc c++ meson ninja tar patch sha256 pkg-config curl; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
mkdir "$work"
mkdir "$work/tools" "$work/src" "$work/archives" "$work/logs"
prefix=$work/install
ln -s "$python" "$work/tools/python3"
cp "$recipe/native-pkg-config.sh" "$work/tools/pkg-config"
chmod 755 "$work/tools/pkg-config"
PATH="$work/tools:$PATH"
PKG_CONFIG="$work/tools/pkg-config"
PKG_CONFIG_PATH=/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig
LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
CFLAGS='-O2 -I/usr/pkg/include -I/usr/X11R7/include'
CXXFLAGS=$CFLAGS
LDFLAGS='-L/usr/lib -L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib'
export PATH PKG_CONFIG PKG_CONFIG_PATH LD_LIBRARY_PATH CFLAGS CXXFLAGS LDFLAGS
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
read -r name expected url < "$recipe/efl-source.tsv"
if [ "$#" = 2 ]; then
    cp "$2" "$work/archives/$name"
else
    curl -fLsS --connect-timeout 20 --max-time 1800 "$url" -o "$work/archives/$name"
fi
actual=$(sha256 -q "$work/archives/$name")
[ "$actual" = "$expected" ] || { echo 'EFL archive checksum mismatch.' >&2; exit 2; }
printf '%s %s %s\n' "$name" "$actual" "$url" > "$work/logs/source.txt"
tar -xf "$work/archives/$name" -C "$work/src"
source=$work/src/efl-1.28.1
for patchfile in "$recipe"/patches/efl/patch-*; do
    run "$(basename "$patchfile")" patch -d "$source" -p0 < "$patchfile"
done
run patch-lua54 patch -d "$source" -p1 < "$recipe/patches/efl/lua54.patch"
pkg-config --atleast-version=5.4 lua && pkg-config --max-version=5.4.99 lua || {
    echo 'This probe uses the shared system Lua 5.4, not a private older Lua.' >&2
    exit 2
}
run setup meson setup "$work/build" "$source" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dx11=true -Dopengl=none -Dpixman=true -Dwl=false -Ddrm=false \
    -Dsystemd=false -Dv4l2=false -Deeze=false -Dinput=false -Dlibmount=false \
    -Dphysics=false -Dgstreamer=false -Dpulseaudio=true \
    -Dlua-interpreter=lua -Dbindings=[] -Dbuild-examples=false -Dbuild-tests=true \
    -Dnative-arch-optimization=false -Ddocs=false \
    -Decore-imf-loaders-disabler=ibus,scim \
    -Devas-loaders-disabler=gst,pdf,ps,raw,jp2k,json,avif,heif,jxl
run compile meson compile -C "$work/build" -j "$jobs"
run install meson install -C "$work/build" --no-rebuild
run abi ldd "$prefix/lib/libelementary.so"
if grep -q 'libintl.so.8\|not found' "$work/logs/abi.log"; then
    echo 'Conflicting gettext ABI detected.' >&2
    exit 1
fi
grep -F '/usr/lib/liblua.so.6' "$work/logs/abi.log" >/dev/null || {
    echo 'EFL must use the NetBSD system Lua 5.4 library.' >&2
    exit 1
}
run lua-api sh "$recipe/tests/lua54/test-api.sh" "$source" "$work/lua-api"
run lua-runtime sh "$recipe/tests/lua54/test-runtime.sh" "$prefix" "$work/lua-runtime"
run upstream-tests meson test -C "$work/build" --no-rebuild --print-errorlogs eina eet-suite eolian
printf 'EFL prefix: %s\nRuntime still requires an X11 server.\n' "$prefix"
