#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted host cross-compiler recipe using Ports sources.
set -eu
[ "$#" -eq 5 ] || {
    echo 'Usage: build.sh EXPORTED_PKGSRC GCC_ARCHIVE SYSROOT NETBSD_TOOLDIR NEW_WORK' >&2
    exit 2
}
profile=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
recipe=$1/lang/gcc16
archive=$2
sysroot=$3
tools=$4
work=$5
for path in "$@"; do
    case "$path" in /*) ;; *) echo 'Absolute paths required.' >&2; exit 2;; esac
    case "$path" in *[!A-Za-z0-9_./-]*) echo 'Use paths without whitespace or shell metacharacters.' >&2; exit 2;; esac
done
jobs=${CROSS_JOBS:-4}
case "$jobs" in ''|*[!0-9]*) jobs=0;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || { echo 'CROSS_JOBS must be positive.' >&2; exit 2; }
[ ! -e "$work" ] && [ ! -L "$work" ] || { echo 'NEW_WORK already exists.' >&2; exit 2; }
[ -f "$sysroot/usr/include/stddef.h" ] || { echo 'Target headers missing.' >&2; exit 2; }
[ -f "$sysroot/usr/pkg/gcc16/lib/gcc/aarch64--netbsd/16.2.0/crtbegin.o" ] || {
    echo 'The sysroot must contain the selected target GCC16 package.' >&2; exit 2;
}
[ -d "$sysroot/usr/pkg/gcc16/include/c++" ] || exit 2
[ -x "$tools/bin/nbgmake" ] || { echo 'Bootstrap GNU make missing.' >&2; exit 2; }
for library in gmp mpfr mpc; do
    [ -f "$tools/lib/lib$library.a" ] || { echo "Bootstrap lib$library.a missing." >&2; exit 2; }
done
expected=$(awk -F '\t' '$1 == "gcc" && $2 == "16.2.0" {print $4}' "$profile/sources.tsv")
[ -n "$expected" ] && [ "$(shasum -a 256 "$archive" | awk '{print $1}')" = "$expected" ] || {
    echo 'GCC archive SHA256 mismatch.' >&2; exit 1;
}
# Verify every recorded source patch, including the native-only patch excluded below.
# The common profile disables Graphite and does not extract or patch ISL.
patches=$(awk '/^SHA1 \(patch-/ && $2 != "(patch-isl_configure)" { gsub(/[()]/, "", $2); print $2 }' "$recipe/distinfo")
[ -n "$patches" ] || { echo 'No recipe patches.' >&2; exit 1; }
for name in $patches; do
    case "$name" in patch-*[!A-Za-z0-9_.-]*|*/*) echo 'Invalid patch name.' >&2; exit 1;; esac
    [ -f "$recipe/patches/$name" ] || { echo "Missing patch: $name" >&2; exit 1; }
    recorded=$(awk -v name="($name)" '$1 == "SHA1" && $2 == name {print $4}' "$recipe/distinfo")
    actual=$(sed '/[$]NetBSD.*/d' "$recipe/patches/$name" | shasum -a 1 | awk '{print $1}')
    [ "$actual" = "$recorded" ] || { echo "Patch SHA1 mismatch: $name" >&2; exit 1; }
done
# This recipe requires the same repaired frontend as the native nb1 package.
printf '%s\n' "$patches" | grep -qx patch-gcc_cp_module.cc || {
    echo 'GCC16 modules repair missing.' >&2; exit 1;
}
mkdir -p "$work"
work=$(CDPATH= cd -- "$work" && pwd -P)
prefix=$work/toolchain
mkdir "$work/src" "$work/build" "$prefix" "$prefix/bin"
{
    uname -srm
    shasum -a 256 "$archive" "$recipe/distinfo" "$recipe"/patches/patch-*
    "$tools/bin/nbgmake" --version
    "$tools/bin/aarch64--netbsd-ld" --version
    printf 'sysroot=%s\nbootstrap=%s\n' "$sysroot" "$tools"
} > "$work/inputs.txt"
tar -xf "$archive" --strip-components=1 -C "$work/src"
for name in $patches; do
    # pkgsrc's native driver embeds its own install prefix as the target RPATH.
    # A cross compiler's Mac prefix must never enter target link inputs/RPATHs.
    [ "$name" != patch-gcc_Makefile.in ] || continue
    patch -f -N -F 0 -p0 -d "$work/src" < "$recipe/patches/$name"
done > "$work/patch.log" 2>&1
for tool in ar as elfedit ld nm objcopy objdump ranlib readelf size strings strip; do
    cp "$tools/bin/aarch64--netbsd-$tool" "$prefix/bin/"
done
cd "$work/build"
unset GCC_EXEC_PREFIX COMPILER_PATH LIBRARY_PATH CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH
CC=${HOST_CC:-cc} CXX=${HOST_CXX:-c++} CFLAGS=-O2 CXXFLAGS=-O2 \
    ../src/configure --target=aarch64--netbsd --prefix="$prefix" \
    --with-sysroot="$sysroot" --with-gxx-include-dir="$sysroot/usr/pkg/gcc16/include/c++" \
    --with-gmp="$tools" --with-mpfr="$tools" --with-mpc="$tools" \
    --with-as="$prefix/bin/aarch64--netbsd-as" --with-ld="$prefix/bin/aarch64--netbsd-ld" \
    --enable-languages=c,c++ --disable-bootstrap --disable-multilib \
    --disable-nls --without-isl > "$work/configure.log" 2>&1
"$tools/bin/nbgmake" -j"$jobs" all-gcc > "$work/build.log" 2>&1
"$tools/bin/nbgmake" install-gcc > "$work/install.log" 2>&1
[ "$("$prefix/bin/aarch64--netbsd-gcc" -dumpfullversion)" = 16.2.0 ]
[ "$("$prefix/bin/aarch64--netbsd-g++" -dumpmachine)" = aarch64--netbsd ]
echo "GCC16 cross compiler built: $prefix"
echo 'Compile the acceptance programs, then run them on EmberBSD before accepting the toolchain.'
