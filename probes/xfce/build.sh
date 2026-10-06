#!/bin/sh
# Build the selected Xfce X11 profile, in dependency order.
set -eu
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build.sh NEW_WORK [ARCHIVE_DIRECTORY]' >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
work=$1
case "${BUILD_MOUSEPAD:-1}" in 0|1) ;; *) echo 'BUILD_MOUSEPAD must be 0 or 1.' >&2; exit 2 ;; esac
sh "$recipe/prepare-sources.sh" "$@"
while read -r component archive expected url; do
    if [ "$component" = mousepad ] && [ "${BUILD_MOUSEPAD:-1}" = 0 ]; then
        continue
    fi
    sh "$recipe/build-component.sh" "$work" "$component"
done < "$recipe/sources.tsv"
printf 'Xfce installed in %s/install; verify a separate X11 session before claiming runtime support.\n' "$work"
