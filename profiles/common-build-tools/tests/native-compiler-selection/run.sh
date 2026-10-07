#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# AI-assisted EmberBSD native pkgsrc compiler-selection check.
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
[ "$#" -eq 3 ] || fail "usage: $0 EXPORTED_PKGSRC MAKECONF NEW_WORK"
pkgsrc=$1
makeconf=$2
work=$3
for path in "$pkgsrc" "$makeconf" "$work"; do
    case "$path" in /*) ;; *) fail "paths must be absolute" ;; esac
    case "$path" in *[[:space:]]*) fail "paths must not contain whitespace" ;; esac
done
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ] ||
    fail "requires native NetBSD/AArch64"
case "$(uname -r)" in 11.*) ;; *) fail "requires NetBSD 11" ;; esac
[ "$(id -u)" -eq 0 ] || fail "pkg_add/pkg_delete require root"
[ -z "${LD_LIBRARY_PATH-}${LD_PRELOAD-}" ] || fail "loader overrides are forbidden"
[ -f "$pkgsrc/mk/bsd.pkg.mk" ] && [ -f "$makeconf" ] || fail "missing inputs"
[ ! -e "$work" ] || fail "work directory already exists"
pkg_info -e "gcc16>=16.2.0nb1" >/dev/null || fail "install repaired GCC16 16.2.0nb1 or newer before this check"
[ "$(/usr/pkg/gcc16/bin/gcc -dumpfullversion)" = 16.2.0 ] || fail "wrong GCC"
for tool in cwrappers mktools checkperms; do
    pkg_info -e "$tool-[0-9]*" >/dev/null || fail "install $tool before this check"
done
name=emberbsd-gcc16-selection-1.0
category=$pkgsrc/emberbsd-native-check
recipe=$category/compiler-selection
bindir=/usr/pkg/libexec/emberbsd-transition
[ ! -e "$category" ] || fail "private test category already exists"
pkg_info -e "$name" >/dev/null 2>&1 && fail "test package already installed"
[ ! -e "$bindir/c-consumer" ] && [ ! -e "$bindir/cxx-consumer" ] ||
    fail "test executable path already exists"
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$work" "$recipe" "$work/distfiles"
cp -R "$here/fixture/." "$recipe/"
cp -R "$here/fixture" "$work/source"
installed=no
cleanup() {
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$installed" = yes ]; then
        pkg_delete "$name" >>"$work/removal.log" 2>&1 || result=1
    fi
    rm -rf "$category"
    echo "$result" >"$work/status"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
make_pkg() {
    (cd "$recipe" && make MAKECONF="$makeconf" \
        WRKOBJDIR="$work/work" PACKAGES="$work/packages" DISTDIR="$work/distfiles" \
        MAKE_JOBS=1 "$@")
}
make_pkg -V 'compiler=${_GCC_PKGBASE}' -V 'prefix=${_GCC_PREFIX}' \
    -V 'floor=${_GCC_REQD}' -V 'runtime=${USE_PKGSRC_GCC_RUNTIME}' -V 'method=${BUILDLINK_DEPMETHOD.gcc16}' \
    -V 'deps=${DEPENDS} ${BUILD_DEPENDS} ${TOOL_DEPENDS}' \
    -V 'fail=${PKG_FAIL_REASON}' >"$work/selection.txt"
grep -Fx compiler=gcc16 "$work/selection.txt" >/dev/null || fail "wrong compiler metadata"
grep -Fx prefix=/usr/pkg/gcc16/ "$work/selection.txt" >/dev/null || fail "wrong compiler prefix"
grep -Fx floor=16.2 "$work/selection.txt" >/dev/null || fail "wrong GCC floor"
grep -Fx runtime=no "$work/selection.txt" >/dev/null || fail "separate GCC runtime selected"
grep -Fx method=full "$work/selection.txt" >/dev/null || fail "missing full GCC dependency"
grep -Fx fail= "$work/selection.txt" >/dev/null || fail "pkgsrc rejected configuration"
grep 'gcc16>=16.2.0nb1' "$work/selection.txt" >/dev/null || fail "missing repaired GCC16 package floor"
if grep gcc16-libs "$work/selection.txt"; then fail "duplicate runtime dependency"; fi
make_pkg package >"$work/package.log" 2>&1
package=$work/packages/All/$name.tgz
tar -xzOf "$package" +CONTENTS >"$work/contents.txt"
grep '^@pkgdep gcc16>=16.2.0nb1' "$work/contents.txt" >/dev/null || fail "missing packaged GCC dependency"
if grep -E 'gcc16-libs|^@(exec|unexec)' "$work/contents.txt"; then fail "unexpected package action"; fi
if tar -tzf "$package" | grep -E '^\+(INSTALL|DEINSTALL)$'; then fail "unexpected package script"; fi
sha256 "$package" "$work/source/files/consumer.c" "$work/source/files/consumer.cc" >"$work/hashes.txt"
pkg_add "$package" >"$work/install.log" 2>&1
installed=yes
"$bindir/c-consumer" >"$work/c-run.txt" 2>&1
"$bindir/cxx-consumer" >"$work/cxx-run.txt" 2>&1
readelf -d "$bindir/cxx-consumer" >"$work/cxx-dynamic.txt"
ldd "$bindir/cxx-consumer" >"$work/cxx-ldd.txt"
# Installed binaries are stripped; stop at the exported throw symbol instead
# of main so the installed runtime remains loaded for inspection.
gdb -q -batch -ex 'set startup-with-shell off' -ex 'set breakpoint pending on' \
    -ex 'break __cxa_throw' -ex run -ex 'info sharedlibrary' -ex continue \
    --args "$bindir/cxx-consumer" >"$work/cxx-loaded.txt" 2>&1
for receipt in "$work/cxx-ldd.txt" "$work/cxx-loaded.txt"; do
    grep -E '/usr/pkg/gcc16/lib/([^[:space:]]*/)?libstdc\+\+\.so\.7' "$receipt" >/dev/null || fail "wrong C++ runtime"
    grep -E '/usr/pkg/gcc16/lib/([^[:space:]]*/)?libgcc_s\.so\.1' "$receipt" >/dev/null || fail "wrong unwind runtime"
    if grep 'libstdc++.so.9' "$receipt"; then fail "base GCC12 C++ runtime loaded"; fi
done
sha256 "$bindir/c-consumer" "$bindir/cxx-consumer" >>"$work/hashes.txt"
pkg_delete "$name" >"$work/removal.log" 2>&1
installed=no
echo 'PASS: native pkgsrc GCC16.2 selection and installed C/C++ runtime'
