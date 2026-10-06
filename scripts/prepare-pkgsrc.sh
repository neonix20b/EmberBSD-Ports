#!/bin/sh
# Prepare a pinned pkgsrc tree with the local EmberBSD recipes.
set -eu
umask 022

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
    echo 'Usage: sh scripts/prepare-pkgsrc.sh ABSOLUTE_NEW_DIRECTORY [development-toolchain]' >&2
    exit 2
}
profile=${2:-}
case "$profile" in
    ''|development-toolchain) ;;
    *) echo 'Unknown profile.' >&2; exit 2 ;;
esac
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
for category in "$root"/pkgsrc/*; do
    [ -d "$category" ] || continue
    name=${category##*/}
    [ ! -e "$destination/$name" ] && [ ! -L "$destination/$name" ] || {
        echo "Upstream already has $name; review the overlay." >&2
        exit 2
    }
    cp -R "$category" "$destination/$name"
done
if [ "$profile" = development-toolchain ]; then
    for delta in pkgsrc-gcc16.2.patch strict-tests.patch current-prerequisites.patch; do
        patch -f -E -d "$destination" -p1 -F 0 < \
            "$root/profiles/development-toolchain/patches/$delta"
    done
    cp "$root/profiles/development-toolchain/mk.conf" \
        "$destination/EMBERBSD-DEVELOPMENT-MK.CONF"
fi
printf '%s\n' "$expected" > "$destination/EMBERBSD-PKGSRC-REVISION"
printf 'Prepared %s with pkgsrc %s\n' "$destination" "$expected"
