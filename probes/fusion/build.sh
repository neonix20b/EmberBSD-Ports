#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
umask 022
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: build.sh ABS_NEW_WORK [ABS_CACHE]' >&2; exit 2; }
work=$1
for directory in "$@"; do
    case "$directory" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$directory" in *[!a-zA-Z0-9_./-]*) echo 'Use paths without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
done
[ ! -e "$work" ] && [ ! -L "$work" ] || { echo 'Work path already exists.' >&2; exit 2; }
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || { echo 'JOBS must be positive.' >&2; exit 2; }
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
for tool in cmake ninja tar; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
if command -v sha256 >/dev/null; then
    digest() { sha256 -q "$1"; }
else
    command -v shasum >/dev/null || { echo 'sha256 or shasum required.' >&2; exit 2; }
    digest() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
fi
[ "$#" = 2 ] || command -v curl >/dev/null
mkdir "$work"
mkdir "$work/src" "$work/archives" "$work/logs"
prefix=$work/install
run()
{
    stage=$1
    shift
    printf '%s\n' "$stage"
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        tail -60 "$work/logs/$stage.log" >&2
        exit "$status"
    fi
}
while read -r name expected url; do
    if [ "$#" = 2 ]; then
        cp "$2/$name" "$work/archives/$name"
    else
        curl -fLsS --connect-timeout 20 --max-time 900 "$url" -o "$work/archives/$name"
    fi
    actual=$(digest "$work/archives/$name")
    [ "$actual" = "$expected" ] || { echo "Checksum mismatch: $name" >&2; exit 2; }
    printf '%s %s %s\n' "$name" "$actual" "$url" >> "$work/logs/sources.txt"
done < "$recipe/sources.tsv"
while read -r name expected url; do
    tar -xf "$work/archives/$name" -C "$work/src"
done < "$recipe/sources.tsv"
{ uname -a; cmake --version; ninja --version; } > "$work/logs/tools.txt"
run fusion-configure cmake -S "$recipe/cmake" -B "$work/fusion-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DFUSION_SOURCE="$work/src/Fusion-1.3.3"
run fusion-build cmake --build "$work/fusion-build" --parallel "$jobs"
run fusion-install cmake --install "$work/fusion-build"
mkdir -p "$prefix/share/ember-fusion/licenses"
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$prefix/share/ember-fusion/"
cp "$work/src/Fusion-1.3.3/LICENSE.md" "$prefix/share/ember-fusion/licenses/Fusion-MIT"
echo "Installed in $prefix; run test.sh next."
