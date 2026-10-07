#!/bin/sh
# Check an installed C consumer; do not confuse this with C++ stack migration.
set -eu
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
[ "$#" = 2 ] || { echo 'Usage: sh check-libwnck.sh PREFIX NEW_OUTPUT_DIRECTORY' >&2; exit 2; }
prefix=$1
output=$2
for path in "$prefix" "$output"; do
    case "$path" in /*) ;; *) exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
done
[ -z "${LD_LIBRARY_PATH:-}${LD_PRELOAD:-}" ] || { echo 'Remove loader overrides for this check.' >&2; exit 2; }
CC=${CC:-/usr/pkg/gcc16/bin/gcc}
recipe=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
PKG_CONFIG_PATH="$prefix/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
export PKG_CONFIG_PATH
[ "$(sh "$recipe/native-pkg-config.sh" --modversion libwnck-3.0)" = 43.3 ]
mkdir "$output"
flags=$(sh "$recipe/native-pkg-config.sh" --cflags --libs libwnck-3.0)
# All prefix paths are restricted above; pkg-config returns compiler flags.
"$CC" -O2 -Wall -Wextra -Werror -D_NETBSD_SOURCE \
    "$recipe/tests/wnck-consumer.c" $flags -Wl,-rpath,"$prefix/lib" \
    -o "$output/wnck-consumer"
"$CC" --version > "$output/compiler.txt"
"$CC" -print-file-name=libgcc_s.so.1 >> "$output/compiler.txt"
"$output/wnck-consumer" > "$output/loaded.txt"
readelf -d "$output/wnck-consumer" > "$output/dynamic.txt"
ldd "$output/wnck-consumer" > "$output/ldd.txt"
loaded=$(awk '$1 == "LOADED" && $2 ~ /\/libwnck-3\.so/ { print $2 }' "$output/loaded.txt")
[ -n "$loaded" ] && [ "$(printf '%s\n' "$loaded" | wc -l | tr -d ' ')" = 1 ]
case "$(realpath "$loaded")" in "$prefix"/lib/*) ;; *) echo 'Wrong libwnck loaded.' >&2; exit 1 ;; esac
for family in libgcc_s.so libstdc++.so; do
    count=$(awk -v family="$family" '$1 == "LOADED" && index($2, family) { n++ } END { print n+0 }' "$output/loaded.txt")
    [ "$count" -le 1 ] || { echo "Multiple $family runtimes loaded." >&2; exit 1; }
done
cat "$output/loaded.txt"
echo 'PASS: installed libwnck C API and a single runtime per family'
echo 'The loaded DSO report is evidence, not acceptance of the common GCC C++ migration.'
