#!/bin/sh
# Origin: EmberBSD; AI-assisted isolated native libdrm metadata build.
# SPDX-License-Identifier: BSD-2-Clause
set -eu
umask 022
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD build required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: build-libdrm.sh ABSOLUTE_NEW_DIRECTORY [ORIGINAL_ARCHIVE]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Absolute build directory required.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a path without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
jobs=${JOBS:-3}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
PATH=/usr/pkg/bin:/usr/bin:/bin
export PATH
for tool in cc meson ninja tar patch sha256 curl; do command -v "$tool" >/dev/null; done
mkdir "$work"
mkdir "$work/src" "$work/log"
read -r name expected url < "$recipe/sources.tsv"
[ "$name" = libdrm-2.4.134.tar.xz ] || { echo 'Unexpected libdrm source pin.' >&2; exit 2; }
if [ "$#" -eq 2 ]; then cp "$2" "$work/$name";
else curl -fLsS --connect-timeout 20 --max-time 300 "$url" -o "$work/$name"; fi
[ "$(sha256 -q "$work/$name")" = "$expected" ] || { echo 'Archive checksum mismatch.' >&2; exit 2; }
printf '%s  %s  %s\n' "$expected" "$name" "$url" > "$work/log/source.txt"
tar -xf "$work/$name" -C "$work/src"
source=$work/src/libdrm-2.4.134
for patch_file in "$recipe/patches/libdrm"/*; do
    patch -d "$source" -p0 < "$patch_file" >> "$work/log/patches.txt"
    sha256 "$patch_file" >> "$work/log/patch-hashes.txt"
done
sh "$recipe/tests/native-identity.sh" "$source" > "$work/log/identity-contract.txt" 2>&1
sed 's/@ATOMIC_OPS_CHECK@/1/g' "$source/xf86drm.h" > "$work/xf86drm.h"
mv "$work/xf86drm.h" "$source/xf86drm.h"
CFLAGS='-O2 -Werror -I/usr/pkg/include'
LDFLAGS="-L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -lpci"
export CFLAGS LDFLAGS
meson setup "$work/build" "$source" --prefix="$work/install" --libdir=lib \
    --buildtype=release --wrap-mode=nodownload \
    -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
    -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dfreedreno=disabled \
    -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled -Dman-pages=disabled \
    -Dcairo-tests=disabled -Dtests=true -Dinstall-test-programs=true > "$work/log/setup.txt" 2>&1
meson compile -C "$work/build" -j "$jobs" > "$work/log/build.txt" 2>&1
meson test -C "$work/build" --no-rebuild --print-errorlogs > "$work/log/tests.txt" 2>&1
meson install -C "$work/build" --no-rebuild > "$work/log/install.txt" 2>&1
printf 'Private libdrm staged at %s/install; live DRM acceptance remains separate.\n' "$work"
