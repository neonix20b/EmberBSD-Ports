#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted upstream source preparation.
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: prepare-sources.sh NEW_WORK_DIRECTORY' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work directory.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
mkdir "$work"
mkdir "$work/archives" "$work/src" "$work/logs"
while read -r digest url; do
    case "$digest" in ''|'#'*) continue ;; esac
    name=${url##*/}
    case "$name" in ''|*[!a-zA-Z0-9._-]*) echo 'Invalid archive name.' >&2; exit 2 ;; esac
    curl -fLsS --connect-timeout 20 --max-time 300 --retry 2 "$url" -o "$work/archives/$name"
    actual=$(sha256 -q "$work/archives/$name")
    [ "$actual" = "$digest" ] || { echo "SHA256 mismatch: $name" >&2; exit 1; }
    printf '%s  %s\n' "$actual" "$url" >> "$work/sources.sha256"
    tar -xf "$work/archives/$name" -C "$work/src"
done < "$recipe/sources.sha256"
for component in plasma-mobile powerdevil; do
    for patchfile in "$recipe/patches/$component/"*.patch; do
        patch -d "$work/src/$component-6.7.5" -p1 < "$patchfile"
    done
done
printf 'Verified sources: %s/src\n' "$work"
