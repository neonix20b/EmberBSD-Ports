#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Build stable awesomeWM and LGI with the operating system's Lua 5.4.
set -eu
umask 077
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin:/usr/bin:/bin
LANG=C.UTF-8
export PATH LANG
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD build required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build-native.sh NEW_WORK [ARCHIVE_DIR]' >&2; exit 2; }
work=$1
archives=${2:-}
for path in "$work" ${archives:+"$archives"}; do
    case "$path" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./-]*) echo 'Use paths without shell metacharacters.' >&2; exit 2 ;; esac
done
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
CC=${CC:-/usr/bin/cc}
export CC
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
for tool in "$CC" /usr/bin/lua gmake cmake ninja tar patch sha256 pkg-config curl bash readelf; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
[ -r /usr/include/lua.h ] && [ -r /usr/lib/liblua.so ]
/usr/bin/lua -e 'assert(_VERSION == "Lua 5.4", "System Lua 5.4 required")'
PKG_CONFIG_PATH=/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig:/usr/lib/pkgconfig
export PKG_CONFIG_PATH
pkg-config --print-errors --exists \
    glib-2.0 gio-2.0 gmodule-2.0 gobject-introspection-1.0 libffi \
    cairo cairo-xcb pangocairo gdk-pixbuf-2.0 x11 xcb xcb-cursor \
    xcb-randr xcb-xtest xcb-xinerama xcb-shape xcb-util xcb-keysyms \
    xcb-icccm xcb-xkb xkbcommon xkbcommon-x11 xcb-xrm xproto \
    libstartup-notification-1.0 libxdg-basedir dbus-1
mkdir "$work"
mkdir "$work/tools" "$work/src" "$work/archives" "$work/logs"
prefix=$work/install
cp "$recipe/native-pkg-config.sh" "$work/tools/pkg-config"
chmod 755 "$work/tools/pkg-config"
PATH="$work/tools:$prefix/bin:$PATH"
PKG_CONFIG="$work/tools/pkg-config"
CFLAGS=${CFLAGS:--O2 -I/usr/pkg/include -I/usr/X11R7/include}
LDFLAGS=${LDFLAGS:--L/usr/lib -L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib}
LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
LUA_PATH="$prefix/share/lua/5.4/?.lua;$prefix/share/lua/5.4/?/init.lua;;"
LUA_CPATH="$prefix/lib/lua/5.4/?.so;;"
export PATH PKG_CONFIG CFLAGS LDFLAGS LD_LIBRARY_PATH LUA_PATH LUA_CPATH
# Check real startup linkage without bypasses inherited from the caller.
unset AWESOME_IGNORE_LGI LD_PRELOAD
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
run lua-abi-compile "$CC" -I/usr/include "$recipe/tests/check-lua-abi.c" \
    /usr/lib/liblua.so -lm -o "$work/tools/check-lua-abi"
run lua-abi "$work/tools/check-lua-abi"
run system-lua-linkage ldd /usr/bin/lua
run system-lua-needed readelf -d /usr/bin/lua
if ! grep -q 'NEEDED.*\[libpthread\.so' "$work/logs/system-lua-needed.log"; then
    echo 'System Lua must link libpthread at startup for LGI worker threads.' >&2
    echo 'Use the EmberBSD Lua CLI fix; see README.md. No alternate Lua is installed.' >&2
    exit 2
fi
run compiler "$CC" --version
run host uname -a
run dependencies pkg-config --modversion glib-2.0 gobject-introspection-1.0 \
    libffi cairo pangocairo gdk-pixbuf-2.0 xcb xkbcommon xcb-xrm libxdg-basedir
while read -r name expected url; do
    if [ -n "$archives" ]; then
        cp "$archives/$name" "$work/archives/$name"
    else
        curl -fLsS --connect-timeout 20 --max-time 1800 "$url" -o "$work/archives/$name"
    fi
    actual=$(sha256 -q "$work/archives/$name")
    [ "$actual" = "$expected" ] || { echo "Archive checksum mismatch: $name" >&2; exit 2; }
    printf '%s %s %s\n' "$name" "$actual" "$url" >> "$work/logs/source.txt"
    tar -xf "$work/archives/$name" -C "$work/src"
done < "$recipe/source.tsv"
lgi=$work/src/lgi-0.9.2
awesome=$work/src/awesome-4.3
run patch-lgi-lua54 patch -F0 -d "$lgi" -p1 < "$recipe/patches/lgi/0001-lua54.patch"
run patch-lgi-require patch -F0 -d "$lgi" -p0 < "$recipe/patches/lgi/0002-glib-require.patch"
run patch-lgi-enums patch -F0 -d "$lgi" -p0 < "$recipe/patches/lgi/0003-glib-enums.patch"
for patchfile in "$recipe"/patches/awesome/*.patch; do
    run "patch-awesome-$(basename "$patchfile" .patch)" patch -F0 -d "$awesome" -p1 < "$patchfile"
done
# Intentional word splitting: pkg-config and compiler flag variables are lists.
run icon-compile "$CC" $CFLAGS $(pkg-config --cflags gdk-pixbuf-2.0) \
    "$recipe/theme-icon.c" $LDFLAGS $(pkg-config --libs gdk-pixbuf-2.0) -lm \
    -o "$work/tools/theme-icon"
run icon-contract sh "$recipe/tests/check-theme-icons.sh" \
    "$work/tools/theme-icon" "$awesome" "$work/icon-contract"
lgi_libs="$(pkg-config --libs gobject-introspection-1.0 gmodule-2.0 libffi) /usr/lib/liblua.so"
run lgi-compile gmake -C "$lgi" -j "$jobs" CC="$CC" \
    PREFIX="$prefix" LUA_VERSION=5.4 LUA_CFLAGS=-I/usr/include \
    PKG_CONFIG="$PKG_CONFIG" LIBS="$lgi_libs"
run lgi-install gmake -C "$lgi" install PREFIX="$prefix" LUA_VERSION=5.4
run lgi-contract /usr/bin/lua "$recipe/tests/check-lgi.lua" "$work/logs/lgi-render.png"
run configure cmake -S "$awesome" -B "$work/build" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DPKG_CONFIG_EXECUTABLE="$PKG_CONFIG" \
    -DAWESOME_ICON_CONVERTER="$work/tools/theme-icon" \
    -DLUA_EXECUTABLE=/usr/bin/lua -DLUA_INCLUDE_DIR=/usr/include \
    -DLUA_LIBRARY=/usr/lib/liblua.so \
    '-DCMAKE_INSTALL_RPATH=/usr/pkg/lib;/usr/X11R7/lib' \
    -DOVERRIDE_VERSION=4.3 -DGENERATE_DOC=OFF -DGENERATE_MANPAGES=OFF \
    -DWITH_DBUS=ON
# NetBSD's Lua omits the current directory from package.path. Generated
# documentation loads build/docs/_parser.lua even when LDoc is disabled.
# Scope the trusted build path to this build command, never runtime exports.
run compile env LUA_PATH="$work/build/?.lua;$LUA_PATH" \
    cmake --build "$work/build" --parallel "$jobs"
run install cmake --install "$work/build"
run version sh "$recipe/tests/check-version.sh" "$prefix/bin/awesome"
run config-check "$prefix/bin/awesome" --check --config "$prefix/etc/xdg/awesome/rc.lua"
run awesome-abi ldd "$prefix/bin/awesome"
run lgi-check-abi ldd "$work/build/lgi-check"
run lgi-abi ldd "$prefix/lib/lua/5.4/lgi/corelgilua51.so"
run awesome-needed readelf -d "$prefix/bin/awesome"
run lgi-check-needed readelf -d "$work/build/lgi-check"
for log in awesome-needed lgi-check-needed; do
    grep -q 'NEEDED.*\[libpthread\.so' "$work/logs/$log.log" || {
        echo "Missing startup pthread linkage: $log" >&2; exit 1;
    }
done
if grep -E 'libintl\.so\.8|not found|luajit|liblua5[123]' "$work/logs/awesome-abi.log" "$work/logs/lgi-abi.log"; then
    echo 'Unexpected library resolution; inspect ABI logs.' >&2
    exit 1
fi
find "$prefix" -type f \( -perm -4000 -o -perm -2000 \) -print > "$work/logs/setid.txt"
[ ! -s "$work/logs/setid.txt" ] || { echo 'Unexpected setid file in prefix.' >&2; exit 1; }
cat > "$work/environment.sh" <<EOF
# Source this file before running this source probe.
PATH='$prefix/bin:/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin'
LUA_PATH='$LUA_PATH'
LUA_CPATH='$LUA_CPATH'
LD_LIBRARY_PATH='$LD_LIBRARY_PATH'
export PATH LUA_PATH LUA_CPATH LD_LIBRARY_PATH
EOF
printf 'awesomeWM prefix: %s\nEnvironment: %s/environment.sh\n' "$prefix" "$work"
