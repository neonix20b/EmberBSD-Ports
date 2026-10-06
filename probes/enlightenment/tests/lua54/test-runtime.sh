#!/bin/sh
# A software-buffer regression; no X server, display change or system install.
set -eu
umask 077
ulimit -c 0
[ "$#" -eq 2 ] || { echo 'Usage: sh test-runtime.sh EFL_PREFIX NEW_TEST_DIRECTORY' >&2; exit 2; }
prefix=$1
work=$2
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
PATH="$prefix/bin:/usr/pkg/bin:/usr/bin:/bin"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
export PATH PKG_CONFIG_PATH LD_LIBRARY_PATH
mkdir "$work"
cp "$recipe/test-lua.edc" "$work/"
# GLib uses native gettext on the target NetBSD environment.
libs=$(pkg-config --libs edje ecore-evas | sed -E 's#(^|[[:space:]])-lintl([[:space:]]|$)#\1/usr/lib/libintl.so.1\2#g')
cc -Wall -Wextra -Werror -O2 $(pkg-config --cflags edje ecore-evas) \
    "$recipe/test-runtime.c" -o "$work/test-runtime" $libs
ldd "$work/test-runtime" > "$work/abi.log"
grep -q '/usr/lib/liblua.so.6' "$work/abi.log"
if grep -E 'liblua5[123]|liblua-5\.[123]|liblua\.so\.[1-5]([[:space:]]|$)' "$work/abi.log"; then
    echo 'An older Lua library entered the test dependency graph.' >&2
    exit 1
fi
edje_cc -fastcomp "$work/test-lua.edc" "$work/test-lua.edj" > "$work/compile-theme.log" 2>&1
"$work/test-runtime" "$work/test-lua.edj" > "$work/runtime.log" 2>&1
cat "$work/runtime.log"
