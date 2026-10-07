#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
umask 022
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build.sh ABS_NEW_WORK [ABS_CACHE]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Absolute work path required.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple work path.' >&2; exit 2 ;; esac
[ ! -e "$work" ] && [ ! -L "$work" ] || { echo 'Work path already exists.' >&2; exit 2; }
cache=${2-}
case "$cache" in ''|/*) ;; *) echo 'Absolute cache path required.' >&2; exit 2 ;; esac
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
JOBS=${JOBS:-1}
case "$JOBS" in ''|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$JOBS" -gt 0 ] || { echo 'JOBS must be positive.' >&2; exit 2; }
CC=${CC:-/usr/bin/gcc}
CXX=${CXX:-/usr/bin/g++}
export CC CXX
# Avoid ambient compiler search paths selecting another private toolchain.
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH LD_LIBRARY_PATH
for tool in sha256 tar curl; do command -v "$tool" >/dev/null; done
mkdir "$work"
mkdir "$work/archives" "$work/src" "$work/logs" "$work/install"
run()
{
    stage=$1; shift
    if "$@" >"$work/logs/$stage.txt" 2>&1; then return; else status=$?; fi
    tail -60 "$work/logs/$stage.txt" >&2
    echo "Failed: $stage" >&2
    exit "$status"
}
# Check every input before extracting any archive.
while IFS="$(printf '\t')" read -r hash archive url; do
    [ -n "$hash" ] || continue
    if [ -n "$cache" ]; then
        cp "$cache/$archive" "$work/archives/$archive"
    else
        curl -fL --connect-timeout 20 --max-time 900 --retry 2 "$url" -o "$work/archives/$archive"
    fi
    [ "$(sha256 -q "$work/archives/$archive")" = "$hash" ] || {
        echo "Source checksum mismatch: $archive; nothing extracted." >&2; exit 1;
    }
done < "$here/sources.tsv"
{
    uname -a
    "$CC" --version
    "$CXX" --version
    sha256 "$work"/archives/*
} > "$work/logs/environment.txt"
command -v unzip >/dev/null
command -v ar >/dev/null
unzip -q "$work/archives/iso14229-0.11.0.zip" -d "$work/src"
[ "$(cat "$work/src/iso14229/VERSION")" = 0.11.0 ] || exit 1
[ "$(sha256 -q "$work/src/iso14229/iso14229.h")" = 30eec21f69f42de2ce02d2f3031c300ca8494b94999bee00c1feedd2adece0ad ] || exit 1
[ "$(sha256 -q "$work/src/iso14229/iso14229.c")" = a22f1c6afe87247a3513f816f37eacb1976a554d7c3dfd33a65911a705f669c5 ] || exit 1
mkdir -p "$work/install/include" "$work/install/lib" "$work/install/share/iso14229-probe"
# This configuration compiles the included user-space isotp-c transport.
# Linux CAN_ISOTP and SocketCAN wrappers are deliberately not selected.
run compile "$CC" -std=c11 -O2 -D_POSIX_C_SOURCE=200809L -DUDS_AUTOSELECT_TP=0 -DUDS_TP_ISOTP_C \
    -c "$work/src/iso14229/iso14229.c" -o "$work/iso14229.o"
run archive ar rcs "$work/install/lib/libiso14229.a" "$work/iso14229.o"
cp "$work/src/iso14229/iso14229.h" "$work/install/include/"
cp "$work/src/iso14229/LICENSE" "$work/src/iso14229/AUTHORS.txt" \
    "$here/sources.tsv" "$here/PROVENANCE.md" "$work/install/share/iso14229-probe/"
echo "Built iso14229 0.11.0 with isotp-c; run: sh $here/test.sh $work"
