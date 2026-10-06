#!/bin/sh
# Build one matching Plasma dependency set into the shared current prefix.
set -eu
recipe_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_root=${BUILD_ROOT:-"$HOME/.cache/emberbsd-plasma-kwin"}
archive_dir=${ARCHIVE_DIR:-"$build_root/archives"}
prefix=${PLASMA_PREFIX:?Set the shared current Plasma installation prefix}
PATH=/usr/pkg/qt6/bin:/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin:/bin:/usr/bin
export PATH LC_ALL=C.UTF-8
: "${CC:=/usr/bin/cc}"
: "${CXX:=/usr/bin/c++}"
export CC CXX
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/X11R7/lib/pkgconfig"
export LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/qt6/lib:/usr/pkg/lib:/usr/X11R7/lib"
mkdir -p "$build_root/src" "$build_root/log"
while read -r expected archive; do
    actual=$(sha256 -q "$archive_dir/$archive")
    [ "$actual" = "$expected" ] || { echo "Checksum mismatch: $archive" >&2; exit 1; }
    name=${archive%.tar.xz}
    [ -d "$build_root/src/$name" ] || tar -xf "$archive_dir/$archive" -C "$build_root/src"
    qt-cmake -S "$build_root/src/$name" -B "$build_root/build-$name" -G Ninja \
        -DCMAKE_C_COMPILER="$CC" \
        -DCMAKE_CXX_COMPILER="$CXX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DCMAKE_PREFIX_PATH="$prefix;/usr/pkg/qt6;/usr/pkg;/usr/X11R7" \
        -DCMAKE_INSTALL_RPATH="$prefix/lib;/usr/pkg/qt6/lib;/usr/pkg/lib;/usr/X11R7/lib" \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        -DBUILD_TESTING=OFF -DBUILD_QCH=OFF
    cmake --build "$build_root/build-$name" --parallel "${JOBS:-1}"
    cmake --install "$build_root/build-$name"
done < "$recipe_dir/kwin-dependencies.sha256"
