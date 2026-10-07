#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted private frontend C++ module acceptance.
set -eu
[ "$#" = 4 ] || { echo 'Usage: modules-native.sh ORIGINAL_ATOM_PRAGMA DRIVER FRONTEND_PREFIX NEW_OUTPUT' >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || { echo 'Native NetBSD required.' >&2; exit 2; }
original=$1
driver=$2
frontend=$3
output=$4
for path in "$original" "$driver" "$frontend" "$output"; do
    case "$path" in /*) ;; *) echo 'Absolute paths required.' >&2; exit 2 ;; esac
done
[ ! -e "$output" ] && [ ! -L "$output" ] || exit 2
[ -x "$driver" ] && [ -x "$frontend/cc1plus" ]
[ "$(sha256 -q "$original")" = a3a4f77b7fd107fbff7cf6b21ebde440db91ce5f0a9a26f0eaafa051e6743307 ]
unset LD_LIBRARY_PATH LD_PRELOAD
ulimit -c 0
mkdir -p "$output/atom" "$output/consumer"
"$driver" --version > "$output/driver-version.txt"
sha256 "$original" "$driver" "$frontend/cc1plus" > "$output/inputs.sha256"
ldd "$frontend/cc1plus" > "$output/frontend-linkage.txt"
cd "$output/atom"
status=0
"$driver" -B"$frontend/" -std=c++20 -pedantic-errors -Wno-long-long -fmodules-ts -S \
    "$original" -o atom-pragma-1.s > compile.log 2>&1 || status=$?
printf '%s\n' "$status" > status
[ "$status" = 0 ] && [ -s atom-pragma-1.s ] && [ -s gcm.cache/foo.gcm ]
sha256 atom-pragma-1.s gcm.cache/foo.gcm > artifacts.sha256
echo 'PASS: unchanged upstream atom-pragma-1.C compiles and writes CMI'
cd "$output/consumer"
cat > answer.cc <<'SOURCE'
export module ember_answer;
export int answer() { return 42; }
SOURCE
cat > main.cc <<'SOURCE'
import ember_answer;
#include <cstdio>
int main() { int value = answer(); std::printf("%d\n", value); return value != 42; }
SOURCE
for unit in answer main; do
    status=0
    "$driver" -B"$frontend/" -std=c++20 -fmodules-ts -c "$unit.cc" -o "$unit.o" \
        > "$unit-compile.log" 2>&1 || status=$?
    printf '%s\n' "$status" > "$unit-status"
    [ "$status" = 0 ]
done
status=0
"$driver" -B"$frontend/" main.o answer.o -o consumer > link.log 2>&1 || status=$?
printf '%s\n' "$status" > link-status
[ "$status" = 0 ]
ldd consumer > linkage.txt
status=0
./consumer > run.log 2>&1 || status=$?
printf '%s\n' "$status" > run-status
[ "$status" = 0 ] && [ "$(cat run.log)" = 42 ]
sha256 answer.cc main.cc answer.o main.o gcm.cache/ember_answer.gcm consumer > artifacts.sha256
echo 'PASS: module export/import/link/run with the existing driver and ordinary loader'
