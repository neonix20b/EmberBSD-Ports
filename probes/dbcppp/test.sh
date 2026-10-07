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
"$CXX" -std=c++17 -O2 -Wall -Wextra -I"$work/install/include" \
    "$here/tests/consumer.cpp" "$work/install/lib/libdbcppp.a" -o "$work/tests/consumer"
"$CC" -std=c11 -O2 -Wall -Wextra -I"$work/install/include" \
    -c "$here/tests/c-api.c" -o "$work/tests/c-api.o"
"$CXX" "$work/tests/c-api.o" "$work/install/lib/libdbcppp.a" -o "$work/tests/c-api"
"$work/tests/consumer" "$here/tests/signals.dbc" "$work/tests/unsupported.kcd" "$here/tests/malformed.dbc" > "$work/logs/consumer.txt" 2>&1 || { status=$?; cat "$work/logs/consumer.txt"; exit "$status"; }
"$work/tests/c-api" "$here/tests/signals.dbc" >> "$work/logs/consumer.txt" 2>&1 || { status=$?; cat "$work/logs/consumer.txt"; exit "$status"; }
cat "$work/logs/consumer.txt"
sha256 "$work/install/lib/libdbcppp.a" "$work/tests/consumer" "$work/tests/c-api" > "$work/logs/artifacts.txt"
ldd "$work/tests/consumer" > "$work/logs/linkage.txt"
