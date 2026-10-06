#!/bin/sh
# Origin: EmberBSD; AI-assisted exhaustive production half conversion test.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: sh mesa-half.sh MESA_SOURCE NEW_WORK' >&2; exit 2; }
source_dir=$(CDPATH= cd -- "$1" && pwd)
work=$2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cc=${CC:-cc}
mkdir "$work"
# Compile complete upstream translation units, without extracting/reimplementing
# the function. These two config facts hold on the named NetBSD/macOS targets.
"$cc" -std=c11 -O2 -DHAVE_PTHREAD -DHAVE_STRUCT_TIMESPEC \
    -I"$source_dir/src" -I"$source_dir/include" \
    "$source_dir/src/util/half_float.c" "$source_dir/src/util/softfloat.c" \
    "$recipe/mesa-half.c" -lm -o "$work/half"
"$work/half"
