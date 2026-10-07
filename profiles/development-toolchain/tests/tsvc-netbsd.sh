#!/bin/sh
# Origin: EmberBSD; AI-assisted native regression for the upstream TSVC backport.
# SPDX-License-Identifier: BSD-2-Clause
set -eu
if [ "$#" -ne 3 ]; then
    echo 'Usage: tsvc-netbsd.sh PRISTINE_GCC_SOURCE EXPORTED_PKGSRC NEW_OUTPUT' >&2
    exit 2
fi
[ "$(uname -s)" = NetBSD ] || { echo 'Native NetBSD required.' >&2; exit 2; }
source_dir=$(CDPATH= cd -- "$1" && pwd)
pkgsrc_dir=$(CDPATH= cd -- "$2" && pwd)
output=$3
case "$output" in /*) ;; *) echo 'Output must be absolute.' >&2; exit 2;; esac
[ ! -e "$output" ] && [ ! -L "$output" ] || exit 2
cc=${CC:-cc}
unset LD_LIBRARY_PATH LD_PRELOAD
tsvc=gcc/testsuite/gcc.dg/vect/tsvc
patch_file=$pkgsrc_dir/lang/gcc16/patches/patch-gcc_testsuite_gcc.dg_vect_tsvc_tsvc.h
test -f "$patch_file"
mkdir -p "$output/baseline/$tsvc" "$output/patched/$tsvc"
for file in tsvc.h vect-tsvc-s000.c license.txt; do
    cp "$source_dir/$tsvc/$file" "$output/baseline/$tsvc/$file"
    cp "$source_dir/$tsvc/$file" "$output/patched/$tsvc/$file"
done
patch -f -N -d "$output/patched" -p0 -F 0 < "$patch_file"
"$cc" --version
sha256 "$source_dir/$tsvc/tsvc.h" "$patch_file"
# Same vectorization options and upstream checksum/scan assertions as vect.exp.
# Use private copies: the original full suite and its compiler are never changed.
for mode in plain lto; do
    set -- -fdiagnostics-plain-output -ftree-vectorize \
        -fno-tree-loop-distribute-patterns -fno-vect-cost-model -fno-common \
        -O2 -fdump-tree-vect-details --param vect-epilogues-nomask=0
    if [ "$mode" = lto ]; then set -- "$@" -flto -ffat-lto-objects; fi
    mkdir "$output/baseline/$mode" "$output/patched/$mode"
    cd "$output/baseline/$mode"
    if "$cc" "$@" "$output/baseline/$tsvc/vect-tsvc-s000.c" -lm -o s000 \
        > compile.log 2>&1; then
        echo "FAIL: baseline unexpectedly compiled ($mode)" >&2
        exit 1
    fi
    grep -q "implicit declaration of function 'memalign'" compile.log
    echo "PASS: baseline fails for undeclared memalign ($mode)"
    cd "$output/patched/$mode"
    "$cc" "$@" "$output/patched/$tsvc/vect-tsvc-s000.c" -lm -o s000 \
        > compile.log 2>&1
    test ! -s compile.log
    ./s000 > run.log 2>&1
    test ! -s run.log
    set -- ./*vect-tsvc-s000.c.*.vect
    [ "$#" -eq 1 ] && [ -f "$1" ]
    [ "$(grep -c 'vectorized 1 loops' "$1")" -eq 1 ]
    echo "PASS: patched compile, upstream runtime checksum and vector scan ($mode)"
done
sha256 "$output/patched/$tsvc/tsvc.h"
