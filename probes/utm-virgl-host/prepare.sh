#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted mechanical upstream patch preparation.
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 ORIGINAL_UTM_ARCHIVE NEW_ABSOLUTE_WORK" >&2; exit 2; }
archive=$1
work=$2
case "$work" in /*) ;; *) echo 'Work path must be absolute' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
hash()
{
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1";
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
[ "$(hash "$archive")" = 6834f45a0b6e904bc8836426657ffcbf13cbc2c2632fb63e6eec57e23670055f ] || {
    echo 'Original archive SHA256 mismatch' >&2; exit 1;
}
original=$recipe/patches/123e0bc-upstream.patch
[ "$(hash "$original")" = a1c804a65190f5d11caa150748e80655f9f98617a7b5711e1529d522cd32e68e ] || {
    echo 'Original upstream patch SHA256 mismatch' >&2; exit 1;
}
mkdir "$work"
mkdir "$work/original" "$work/patched"
tar -xzf "$archive" -C "$work/original" --strip-components=1
tar -xzf "$archive" -C "$work/patched" --strip-components=1
# Only local helper spelling and known hunk locations differ; no code rewrite.
sed -e 's/virgl_get_iovec_size/vrend_get_iovec_size/g' \
    -e 's/@@ -9167,16 +9167,16/@@ -9376,16 +9376,16/' \
    -e 's/@@ -9190,16 +9190,19/@@ -9399,16 +9399,19/' \
    "$original" > "$work/123e0bc-utm.patch"
[ "$(hash "$work/123e0bc-utm.patch")" = 8ea940b70f7ee4563ed4dc36e5d835a3ec9347fdcf65523bb9e891659906b1d7 ] || {
    echo 'Adapted patch SHA256 mismatch' >&2; exit 1;
}
patch -f -N -F 0 -d "$work/patched" -p1 < "$work/123e0bc-utm.patch" > "$work/patch.log" 2>&1
if grep -E 'fuzz|offset|FAILED|Reversed' "$work/patch.log"; then
    echo 'Unexpected patch application' >&2; exit 1
fi
[ "$(hash "$work/patched/src/vrend/vrend_renderer.c")" = 34d99a5726459112444cab327e1ed7849fc732e7e3a5704dbfa641dc05747c87 ] || {
    echo 'Patched renderer SHA256 mismatch' >&2; exit 1;
}
printf '%s\n' 'Prepared pinned original and patched UTM renderer sources; no host build/install.'
