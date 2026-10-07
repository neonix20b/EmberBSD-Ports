#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted private or installed frontend C++ module acceptance.
set -eu
[ "$#" = 4 ] || { echo 'Usage: modules-native.sh ORIGINAL_ATOM_PRAGMA DRIVER FRONTEND_PREFIX_OR_installed NEW_OUTPUT' >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || { echo 'Native NetBSD required.' >&2; exit 2; }
original=$1
driver=$2
frontend=$3
output=$4
for path in "$original" "$driver" "$output"; do
    case "$path" in /*) ;; *) echo 'Absolute paths required.' >&2; exit 2 ;; esac
done
[ ! -e "$output" ] && [ ! -L "$output" ] || exit 2
[ -x "$driver" ]
if [ "$frontend" = installed ]; then
    [ -z "${GCC_EXEC_PREFIX-}${COMPILER_PATH-}" ] || {
        echo 'Installed mode forbids frontend search overrides.' >&2; exit 2;
    }
    frontend_file=$("$driver" -print-prog-name=cc1plus)
    case "$frontend_file" in /*) ;; *) echo 'Installed cc1plus must resolve absolutely.' >&2; exit 2 ;; esac
    set --
    mode=installed
else
    case "$frontend" in /*) ;; *) echo 'Absolute frontend prefix required.' >&2; exit 2 ;; esac
    frontend_file=$frontend/cc1plus
    set -- -B"$frontend/"
    mode=private
fi
[ -x "$frontend_file" ]
[ "$(sha256 -q "$original")" = a3a4f77b7fd107fbff7cf6b21ebde440db91ce5f0a9a26f0eaafa051e6743307 ]
unset LD_LIBRARY_PATH LD_PRELOAD
ulimit -c 0
mkdir -p "$output/atom" "$output/consumer"
"$driver" --version > "$output/driver-version.txt"
printf '%s\n' "$mode" > "$output/frontend-mode.txt"
printf '%s\n' "$frontend_file" > "$output/frontend-path.txt"
sha256 "$original" "$driver" "$frontend_file" > "$output/inputs.sha256"
ldd "$frontend_file" > "$output/frontend-linkage.txt"
cd "$output/atom"
status=0
"$driver" "$@" -std=c++20 -pedantic-errors -Wno-long-long -fmodules-ts -S \
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
    "$driver" "$@" -std=c++20 -fmodules-ts -c "$unit.cc" -o "$unit.o" \
        > "$unit-compile.log" 2>&1 || status=$?
    printf '%s\n' "$status" > "$unit-status"
    [ "$status" = 0 ]
done
status=0
"$driver" "$@" main.o answer.o -o consumer > link.log 2>&1 || status=$?
printf '%s\n' "$status" > link-status
[ "$status" = 0 ]
ldd consumer > linkage.txt
status=0
./consumer > run.log 2>&1 || status=$?
printf '%s\n' "$status" > run-status
[ "$status" = 0 ] && [ "$(cat run.log)" = 42 ]
sha256 answer.cc main.cc answer.o main.o gcm.cache/ember_answer.gcm consumer > artifacts.sha256
echo 'PASS: module export/import/link/run with the existing driver and ordinary loader'
