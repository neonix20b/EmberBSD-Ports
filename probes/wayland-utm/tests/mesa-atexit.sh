#!/bin/sh
# Origin: EmberBSD; AI-assisted production-helper DSO regression.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: sh mesa-atexit.sh MESA_SOURCE NEW_WORK' >&2; exit 2; }
source_dir=$(CDPATH= cd -- "$1" && pwd)
work=$2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cc=${CC:-cc}
cxx=${CXX:-c++}
mkdir "$work"
"$cc" -std=c11 -Wall -Wextra -Werror -I"$source_dir/src" \
    "$recipe/mesa-atexit-failure.c" -o "$work/failure"
"$work/failure"
[ "$(uname -s)" = NetBSD ] || {
    echo 'Native DSO checks require NetBSD; only injected boundary checks ran.'
    exit 0
}
ulimit -c 0
"$cc" -std=c11 -Wall -Wextra -Werror -fPIC -fvisibility=hidden \
    -I"$source_dir/src" -c "$source_dir/src/util/u_atexit.c" -o "$work/helper.o"
for id in 1 2; do
    "$cxx" -std=c++17 -Wall -Wextra -Werror -fPIC -fvisibility=hidden \
        -I"$source_dir/src" -DDSO_ID="$id" -shared -pthread \
        "$recipe/mesa-atexit-dso.cpp" "$work/helper.o" -o "$work/owner$id.so"
    nm -g "$work/owner$id.so" > "$work/owner$id.nm"
    # Both helper and __dso_handle must resolve locally in each owning DSO.
    if grep -E ' (U|T|D|B|W) (util_atexit|__dso_handle)$' "$work/owner$id.nm"; then
        echo 'Non-local DSO lifetime symbol' >&2
        exit 1
    fi
    readelf -sW "$work/owner$id.so" > "$work/owner$id.symbols"
done
"$cc" -std=c11 -Wall -Wextra -Werror -Wl,-export-dynamic \
    "$recipe/mesa-atexit-main.c" -o "$work/main"
"$work/main" close "$work/owner1.so" "$work/owner2.so" > "$work/close.log"
"$work/main" exit "$work/owner1.so" "$work/owner2.so" > "$work/exit.log"
printf 'event 24\nevent 23\nevent 22\nevent 21\nevent 14\nevent 13\nevent 12\nevent 11\n' > "$work/exit.expected"
cmp "$work/exit.expected" "$work/exit.log"
tail -1 "$work/close.log"
echo 'normal exit and mixed C++/C callback order: PASS'
# The same production helper through its plain-atexit path reproduces the
# original NetBSD defect. No callback implementation is copied into this test.
cat > "$work/plain.c" <<END_PLAIN
#include <stdlib.h>
#undef __NetBSD__
#include "util/u_atexit.c"
END_PLAIN
"$cc" -std=c11 -Wall -Wextra -Werror -fPIC -fvisibility=hidden \
    -I"$source_dir/src" -c "$work/plain.c" -o "$work/plain.o"
"$cxx" -std=c++17 -Wall -Wextra -Werror -fPIC -fvisibility=hidden \
    -I"$source_dir/src" -DDSO_ID=1 -shared -pthread \
    "$recipe/mesa-atexit-dso.cpp" "$work/plain.o" -o "$work/plain.so"
status=0
"$work/main" close "$work/plain.so" "$work/owner2.so" > "$work/plain.log" 2>&1 || status=$?
[ "$status" -ne 0 ] || { echo "Plain atexit unexpectedly passed unload" >&2; exit 1; }
grep -q "missing queue cleanup before C++ owner destruction" "$work/plain.log"
printf "plain atexit red control failed as expected (%s)\n" "$status"
