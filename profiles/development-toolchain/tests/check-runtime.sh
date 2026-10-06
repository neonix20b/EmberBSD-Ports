#!/bin/sh
set -eu
[ "$#" -eq 2 ] || exit 2
prefix=$1
output=$2
cxx=$prefix/bin/g++
# Check actual in-process runtime identities, not just link-time search paths.
for library in libstdc++.so libgcc_s.so; do
    awk -v library="$library" '$1 == "LOADED" && index($2, library) {print $2}' \
        "$output/loaded.txt" > "$output/$library.paths"
    [ "$(wc -l < "$output/$library.paths" | tr -d ' ')" = 1 ] || {
        echo "Expected one loaded $library" >&2; exit 1;
    }
    loaded=$(cat "$output/$library.paths")
    actual=$(realpath "$loaded")
    # GCC's t-slibgcc-libgcc makes libgcc_s.so a GNU ld GROUP script.
    # Compare the loaded DSO with the compiler's real SONAME lookup.
    lookup=$library
    [ "$library" != libgcc_s.so ] || lookup=libgcc_s.so.1
    expected=$(realpath "$("$cxx" -print-file-name="$lookup")")
    [ "$actual" = "$expected" ] || { echo "Wrong runtime: $actual != $expected" >&2; exit 1; }
    case "$actual" in "$prefix"/*) ;; *) echo "Runtime outside prefix: $actual" >&2; exit 1 ;; esac
done
