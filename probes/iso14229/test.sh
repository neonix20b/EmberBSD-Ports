#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: sh test.sh ABS_WORK' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Absolute work path required.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CC=${CC:-/usr/bin/gcc}
CXX=${CXX:-/usr/bin/g++}
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH LD_LIBRARY_PATH
[ -d "$work/install" ] && [ -d "$work/logs" ] || exit 2
mkdir -p "$work/tests"
# Exact installed archive paths prevent silently using a system library.
"$CC" -std=c11 -O2 -Wall -Wextra -DUDS_AUTOSELECT_TP=0 -DUDS_TP_ISOTP_C -I"$work/install/include" \
    "$here/tests/consumer.c" "$work/install/lib/libiso14229.a" -o "$work/tests/consumer"
"$work/tests/consumer" > "$work/logs/consumer.txt" 2>&1 || { status=$?; cat "$work/logs/consumer.txt"; exit "$status"; }
cat "$work/logs/consumer.txt"
sha256 "$work/install/lib/libiso14229.a" "$work/tests/consumer" > "$work/logs/artifacts.txt"
ldd "$work/tests/consumer" > "$work/logs/linkage.txt"
