#!/bin/sh
# Build KWin 6.7.5 against the installed Qt/KDE stack on NetBSD 11.
set -eu
recipe_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_root=${BUILD_ROOT:-"$HOME/.cache/emberbsd-plasma-kwin"}
archive_dir=${ARCHIVE_DIR:-"$build_root/archives"}
plasma_prefix=${PLASMA_PREFIX:?Set PLASMA_PREFIX to the matching Plasma installation}
input_prefix=${LIBINPUT_PREFIX:?Set LIBINPUT_PREFIX to the validated libopeninput installation}
source_archive=${SOURCE_ARCHIVE:-"$archive_dir/kwin-6.7.5.tar.xz"}
prefix=${PREFIX:-"$build_root/install"}
PATH=/usr/pkg/qt6/bin:/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin:/bin:/usr/bin
export PATH
export PKG_CONFIG_PATH="$plasma_prefix/lib/pkgconfig:$input_prefix/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/X11R7/lib/pkgconfig"
export LD_LIBRARY_PATH="$plasma_prefix/lib:$input_prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
expected=6baa910b732d93c48c90f9c1cc685cc93d0b8de0cdf138c24192c045bc3a48e2
actual=$(sha256 -q "$source_archive")
[ "$actual" = "$expected" ] || { echo 'KWin archive checksum mismatch' >&2; exit 1; }
mkdir -p "$build_root/src" "$build_root/log"
manifest="$expected kwin-6.7.5.tar.xz"
for patch_file in "$recipe_dir"/patches-6.7.5/*.patch; do
    patch_digest=$(sha256 -q "$patch_file")
    manifest="$manifest
$patch_digest ${patch_file##*/}"
done
source_fingerprint=$(printf '%s\n' "$manifest" | sha256 -q)
stamp="$build_root/src/.patched-6.7.5"
if [ -d "$build_root/src/kwin-6.7.5" ]; then
    if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$source_fingerprint" ]; then
        echo 'Prepared KWin source does not match the archive and patch manifest.' >&2
        echo 'Preserve the existing tree and select a fresh BUILD_ROOT; it will not be overwritten.' >&2
        exit 1
    fi
else
    # An old stamp must not validate an interrupted fresh extraction.
    rm -f "$stamp"
    tar -xf "$source_archive" -C "$build_root/src"
    for patch_file in "$recipe_dir"/patches-6.7.5/*.patch; do
        patch -F 0 -d "$build_root/src/kwin-6.7.5" -p0 < "$patch_file"
    done
    printf '%s\n' "$source_fingerprint" > "$stamp"
fi
if [ "${PREPARE_ONLY:-0}" = 1 ]; then
    echo "Prepared source fingerprint: $source_fingerprint"
    exit 0
fi
qt-cmake -S "$build_root/src/kwin-6.7.5" -B "$build_root/build-6.7.5" -G Ninja \
    -DCMAKE_C_COMPILER=/usr/bin/cc \
    -DCMAKE_CXX_COMPILER=/usr/bin/c++ \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_PREFIX_PATH="$plasma_prefix;$input_prefix;/usr/pkg/qt6;/usr/pkg;/usr/X11R7" \
    -DCMAKE_INSTALL_RPATH="$prefix/lib;$plasma_prefix/lib;$input_prefix/lib;/usr/pkg/qt6/lib;/usr/pkg/lib;/usr/X11R7/lib" \
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
    -DBUILD_TESTING=OFF \
    -DKWIN_BUILD_KCMS=OFF \
    -DKWIN_BUILD_SCREENLOCKER=OFF \
    -DKWIN_BUILD_GLOBALSHORTCUTS=OFF \
    -DKWIN_BUILD_RUNNERS=OFF \
    -DKWIN_BUILD_DECORATIONS=OFF
cmake --build "$build_root/build-6.7.5" --parallel "${JOBS:-1}"
cmake --install "$build_root/build-6.7.5"
