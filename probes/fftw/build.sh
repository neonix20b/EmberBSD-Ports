#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
umask 022
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: build.sh ABS_NEW_WORK [ABS_CACHE]' >&2; exit 2; }
work=$1
for directory in "$@"; do
    case "$directory" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$directory" in *[!a-zA-Z0-9_./-]*) echo 'Use simple paths.' >&2; exit 2 ;; esac
done
[ ! -e "$work" ] && [ ! -L "$work" ] || { echo 'Work path already exists.' >&2; exit 2; }
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || exit 2
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
make=${MAKE:-gmake}
for tool in "$make" tar "${CC:-cc}"; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
if command -v sha256 >/dev/null; then
    digest() { sha256 -q "$1"; }
else
    command -v shasum >/dev/null || exit 2
    digest() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
fi
[ "$#" = 2 ] || command -v curl >/dev/null
mkdir "$work"
mkdir "$work/src" "$work/archives" "$work/logs" "$work/double-build" "$work/float-build"
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
    [ "$(digest "$work/archives/$name")" = "$expected" ] || { echo "Checksum mismatch: $name" >&2; exit 2; }
    printf '%s %s %s\n' "$name" "$expected" "$url" >> "$work/logs/sources.txt"
done < "$recipe/sources.tsv"
tar -xf "$work/archives/fftw-3.3.11.tar.gz" -C "$work/src"
{ uname -a; "${CC:-cc}" --version; "$make" --version; } > "$work/logs/tools.txt"
for precision in double float; do
    (
        cd "$work/$precision-build"
        if [ "$precision" = float ]; then set -- --enable-float; else set --; fi
        run "$precision-configure" "$work/src/fftw-3.3.11/configure" \
            --prefix="$prefix" --libdir="$prefix/lib" --enable-shared --disable-static \
            --enable-threads --disable-fortran --disable-doc "$@"
        run "$precision-build" "$make" -j "$jobs"
        run "$precision-install" "$make" install
    )
done
mkdir -p "$prefix/share/ember-fftw/licenses"
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$prefix/share/ember-fftw/"
cp "$work/src/fftw-3.3.11/COPYING" "$prefix/share/ember-fftw/licenses/FFTW-GPL-2.0-or-later"
printf '%s\n' '3.3.11 double float pthread shared' > "$prefix/share/ember-fftw/profile.txt"
echo "Installed in $prefix; run test.sh next."
