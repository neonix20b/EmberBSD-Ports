#!/bin/sh
# Origin: EmberBSD, AI-assisted. Link real upstream objects, fake only ioctl.
set -eu
[ "$#" -eq 3 ] || { echo 'Usage: wscons-absolute.sh SOURCE BUILD OUTPUT' >&2; exit 2; }
source=$1
build=$2
output=$3
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
set -- "$build"/libinput.so.*.p/*.o
objects=
for object do
    case "$object" in *src_wscons.c.o) ;; *) objects="$objects $object" ;; esac
done
cc -O2 -I"$build" -I"$source/src" -I"$source/include" \
    -I/usr/pkg/include -I/usr/pkg/include/linux -I/usr/pkg/include/libepoll-shim \
    -I"$source" "$recipe/wscons-absolute.c" $objects \
    "$build/liblibinput-util.a" "$build/liblibinput-util-libinput.a" \
    $(pkg-config --libs libudev) -L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib \
    -lepoll-shim -lm -lrt -o "$output"
"$output"
