#!/bin/sh
# SPDX-License-Identifier: MIT
# Disposable source-validation prefix; use pkgsrc for the system installation.
set -eu
umask 022
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build.sh NEW_WORK [ARCHIVE_DIRECTORY]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work directory.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a path without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for tool in cc gmake sha256 tar curl; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
mkdir "$work"
mkdir "$work/archives" "$work/src" "$work/logs"
archive=sqlite-autoconf-3530400.tar.gz
if [ "$#" -eq 2 ]; then
    cp "$2/$archive" "$work/archives/$archive"
else
    curl -fsSL --connect-timeout 10 --max-time 120 \
        "https://www.sqlite.org/2026/$archive" -o "$work/archives/$archive"
fi
expected=0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c
[ "$(sha256 -q "$work/archives/$archive")" = "$expected" ] || {
    echo 'Source checksum mismatch; nothing extracted.' >&2; exit 1;
}
tar -xzf "$work/archives/$archive" -C "$work/src"
cd "$work/src/sqlite-autoconf-3530400"
{
    uname -a
    cc --version
    sha256 "$work/archives/$archive"
} > "$work/logs/environment.txt"
# The autoconf archive contains the amalgamation and autosetup's C Tcl helper.
# No project-owned or upstream Python step is used by this configuration.
run()
{
    stage=$1
    shift
    if "$@" > "$work/logs/$stage.txt" 2>&1; then return; fi
    tail -40 "$work/logs/$stage.txt" >&2
    echo "Failed: $stage" >&2
    exit 1
}
run configure ./configure --prefix="$work/install" --enable-threadsafe --fts5 --disable-readline
run build nice -n 10 gmake -j1
run install gmake install
mkdir -p "$work/install/share/sqlite-probe"
cp "$here/sources.tsv" "$here/PROVENANCE.md" "$work/install/share/sqlite-probe/"
cp autosetup/LICENSE "$work/install/share/sqlite-probe/autosetup-LICENSE"
echo "Installed current SQLite into disposable prefix: $work/install"
echo 'Run check.sh and the local-knowledge consumer with its pkg-config metadata.'
