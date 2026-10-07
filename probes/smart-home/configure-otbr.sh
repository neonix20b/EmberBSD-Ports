#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# AI-assisted native source candidate; this script does not start routing.
set -eu
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
    echo 'Usage: configure-otbr.sh NEW_WORK SHARED_DEPENDENCY_PREFIX [ARCHIVE_CACHE]' >&2
    exit 2
}
work=$1
dependencies=$2
case "$dependencies" in /*) ;; *) exit 2 ;; esac
case "$dependencies" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
CC=${CC:-/usr/pkg/gcc16/bin/gcc}
CXX=${CXX:-/usr/pkg/gcc16/bin/g++}
export CC CXX
for tool in "$CC" "$CXX" cmake ninja pkg-config; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
case "$("$CC" -dumpfullversion)" in 16.2.*) ;; *) echo 'Use common GCC16.2.' >&2; exit 2 ;; esac
[ "$("$CC" -dumpfullversion)" = "$("$CXX" -dumpfullversion)" ] || {
    echo 'C and C++ must use the same common compiler version.' >&2; exit 2
}
PKG_CONFIG_PATH=$dependencies/lib/pkgconfig
export PKG_CONFIG_PATH
[ "$(pkg-config --modversion libcjson)" = 1.7.19 ] || {
    echo 'Use the shared cJSON1.7.19 candidate; do not build an older bundled copy.' >&2
    exit 2
}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -eq 3 ]; then sh "$here/prepare.sh" otbr "$work" "$3"
else sh "$here/prepare.sh" otbr "$work"; fi
patch -f -N -F 0 -p1 -d "$work/source/third_party/openthread/repo" \
    < "$here/patches/otbr-netbsd-curses.patch" > "$work/logs/patch.log"
patch -f -N -F 0 -p1 -d "$work/source/third_party/openthread/repo" \
    < "$here/patches/otbr-netbsd-infra.patch" >> "$work/logs/patch.log"
runtime=$(dirname "$("$CXX" -print-file-name=libstdc++.so)")
result=0
cmake -S "$work/source" -B "$work/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$work/install" \
    -DCMAKE_PREFIX_PATH="$dependencies;/usr/pkg" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_RPATH="$dependencies/lib;$runtime" \
    -DOTBR_VERSION=2026.10.0 -DOTBR_VENDOR_NAME=EmberBSD \
    -DOTBR_MDNS=openthread -DOTBR_REST=ON -DOTBR_DBUS=OFF -DOTBR_WEB=OFF \
    -DOTBR_BORDER_ROUTING=ON -DOTBR_BACKBONE_ROUTER=ON -DOTBR_TREL=ON \
    -DOTBR_NAT64=ON -DOT_FIREWALL=OFF -DOTBR_NFTABLES=OFF -DOTBR_PF=OFF \
    -DOT_POSIX_SETTINGS_PATH="\"$work/settings\"" \
    -DBUILD_TESTING=OFF -DENABLE_TESTING=OFF -DENABLE_PROGRAMS=OFF \
    > "$work/logs/configure.log" 2>&1 || result=$?
if [ "$result" -ne 0 ]; then tail -60 "$work/logs/configure.log" >&2; exit "$result"; fi
ninja -C "$work/build" -n > "$work/logs/build-plan.txt"
echo "Configured OTBR candidate: $work/build"
echo 'No native compilation or routing acceptance yet. Ingress firewall integration is pending.'
