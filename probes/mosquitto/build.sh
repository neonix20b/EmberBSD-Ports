#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# AI-assisted EmberBSD native MQTT source probe; original sources stay upstream.
set -eu
umask 022
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: build.sh NEW_WORK [ARCHIVE_CACHE]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work directory.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple work path.' >&2; exit 2 ;; esac
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CC=${CC:-/usr/pkg/gcc16/bin/gcc}
CXX=${CXX:-/usr/pkg/gcc16/bin/g++}
export CC CXX
for tool in "$CC" "$CXX" cmake ninja gmake sha256 tar curl pkg-config; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
case "$("$CC" -dumpfullversion)" in 16.2.*) ;; *) echo 'Use the common GCC 16.2 toolchain.' >&2; exit 2 ;; esac
[ "$("$CC" -dumpfullversion)" = "$("$CXX" -dumpfullversion)" ] || exit 2
mkdir "$work"
mkdir "$work/archives" "$work/source" "$work/logs"
prefix=$work/install
run()
{
    stage=$1
    shift
    result=0
    "$@" > "$work/logs/$stage.log" 2>&1 || result=$?
    if [ "$result" -ne 0 ]; then
        tail -50 "$work/logs/$stage.log" >&2
        echo "Failed: $stage ($result)" >&2
        exit "$result"
    fi
}
# Reuse the single current SQLite source selection owned by its existing probe.
cat "$here/sources.tsv" "$here/../sqlite/sources.tsv" > "$work/logs/sources.tsv"
while read -r archive expected url; do
    case "$archive" in ''|'#'*) continue ;; esac
    if [ "$#" -eq 2 ]; then
        cp "$2/$archive" "$work/archives/$archive"
    else
        curl -fLsS --connect-timeout 15 --max-time 180 "$url" -o "$work/archives/$archive"
    fi
    [ "$(sha256 -q "$work/archives/$archive")" = "$expected" ] || {
        echo "Checksum mismatch: $archive; nothing extracted." >&2; exit 2;
    }
done < "$work/logs/sources.tsv"
for archive in "$work"/archives/*.tar.gz; do tar -xzf "$archive" -C "$work/source"; done
{
    uname -a
    "$CC" --version
    "$CXX" --version
    cmake --version
    pkg-config --modversion openssl
} > "$work/logs/environment.txt"
runtime=$(dirname "$("$CXX" -print-file-name=libstdc++.so)")
run cjson-configure cmake -S "$work/source/cJSON-1.7.19" -B "$work/cjson-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DENABLE_CJSON_TEST=ON -DENABLE_CJSON_UNINSTALL=OFF
run cjson-build cmake --build "$work/cjson-build" --parallel 1
run cjson-test ctest --test-dir "$work/cjson-build" --output-on-failure
run cjson-install cmake --install "$work/cjson-build"
mkdir "$work/sqlite-build"
cd "$work/sqlite-build"
run sqlite-configure "$work/source/sqlite-autoconf-3530400/configure" \
    --prefix="$prefix" --enable-threadsafe --fts5 --disable-readline
run sqlite-build gmake -j1
run sqlite-install gmake install
cd "$work"
run configure cmake -S "$work/source/mosquitto-2.1.2" -B "$work/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_PREFIX_PATH="$prefix;/usr/pkg" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_RPATH="$prefix/lib;$runtime" \
    -DWITH_TLS=ON -DWITH_THREADING=ON -DWITH_WEBSOCKETS=ON \
    -DWITH_LIB_CPP=ON -DWITH_CLIENTS=ON -DWITH_BROKER=ON -DWITH_PLUGINS=ON \
    -DWITH_PLUGIN_PERSIST_SQLITE=ON -DWITH_PLUGIN_EXAMPLES=OFF \
    -DWITH_CTRL_SHELL=OFF -DWITH_HTTP_API=OFF -DWITH_TESTS=OFF \
    -DWITH_DOCS=OFF -DWITH_LTO=OFF -DWITH_SYSTEMD=OFF
run build cmake --build "$work/build" --parallel 1
run install cmake --install "$work/build"
mkdir -p "$prefix/share/ember-mosquitto/licenses"
cp "$work/logs/sources.tsv" "$prefix/share/ember-mosquitto/"
cp "$work/source/mosquitto-2.1.2/LICENSE.txt" "$prefix/share/ember-mosquitto/licenses/Mosquitto"
cp "$work/source/cJSON-1.7.19/LICENSE" "$prefix/share/ember-mosquitto/licenses/cJSON"
echo "Installed MQTT candidate: $prefix; runtime acceptance still required."
