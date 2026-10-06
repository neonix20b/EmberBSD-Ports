#!/bin/sh
# Compile the two upstream allocation functions, not a duplicate implementation.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: sh test-shm.sh GTK_SOURCE NEW_TEST_DIRECTORY' >&2; exit 2; }
source=$1
work=$2
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
pkg_config=$recipe/../native-pkg-config.sh
mkdir "$work"
awk '/^static int$/ { copy = 1 } /^static void$/ { if (copy) exit } copy { print }' \
    "$source/gdk/wayland/gdkshm.c" > "$work/gtk-shm-functions.c"
grep -q '^create_shm_pool ' "$work/gtk-shm-functions.c"
cp "$recipe/test-shm.c" "$work/"
for mode in memfd shm-open; do
    flags=
    [ "$mode" != shm-open ] || flags=-DTEST_SHM_OPEN
    # pkg-config output is deliberately split into compiler arguments.
    cc -Wall -Wextra -O2 $flags $(sh "$pkg_config" --cflags glib-2.0) \
        "$work/test-shm.c" -o "$work/test-$mode" $(sh "$pkg_config" --libs glib-2.0) -lrt
    "$work/test-$mode"
done
