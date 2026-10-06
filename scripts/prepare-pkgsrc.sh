#!/bin/sh
# Prepare a pinned pkgsrc tree with the local EmberBSD recipes.
set -eu
umask 022

[ "$#" -eq 1 ] || { echo 'Usage: sh scripts/prepare-pkgsrc.sh ABSOLUTE_NEW_DIRECTORY' >&2; exit 2; }
destination=$1
case "$destination" in
    /*) ;;
    *) echo 'Destination must be absolute.' >&2; exit 2 ;;
esac
case "$destination" in
    *[!a-zA-Z0-9_./-]*) echo 'pkgsrc requires a path without whitespace or shell metacharacters.' >&2; exit 2 ;;
esac
[ ! -e "$destination" ] && [ ! -L "$destination" ] || { echo 'Destination already exists.' >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
expected=$(git -C "$root" ls-files --stage -- upstream/pkgsrc | awk '$1 == "160000" { print $2 }')
actual=$(git -C "$root/upstream/pkgsrc" rev-parse HEAD)
[ -n "$expected" ] && [ "$actual" = "$expected" ] || {
    echo 'Initialize the pinned submodule with git submodule update --init upstream/pkgsrc.' >&2
    exit 2
}
archive=$(mktemp "${TMPDIR:-/tmp}/ember-pkgsrc.XXXXXXXX")
trap 'rm -f "$archive"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
git -C "$root/upstream/pkgsrc" archive --format=tar --output="$archive" "$expected"
mkdir "$destination"
tar -xf "$archive" -C "$destination"
[ ! -e "$destination/local-ai" ] || { echo 'Upstream already has local-ai; review the overlay.' >&2; exit 2; }
cp -R "$root/pkgsrc/local-ai" "$destination/local-ai"
printf '%s\n' "$expected" > "$destination/EMBERBSD-PKGSRC-REVISION"
printf 'Prepared %s with pkgsrc %s\n' "$destination" "$expected"
