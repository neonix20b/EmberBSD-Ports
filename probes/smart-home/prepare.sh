#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# AI-assisted preparation of original smart-home sources, without installation.
set -eu
umask 022
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
    echo 'Usage: prepare.sh {domoticz|zigbee2mqtt|otbr|home-assistant} NEW_WORK [ARCHIVE_CACHE]' >&2
    exit 2
}
component=$1
work=$2
case "$component" in domoticz|zigbee2mqtt|otbr|home-assistant) ;; *) exit 2 ;; esac
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple work path.' >&2; exit 2 ;; esac
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
manifest=$here/sources/$component.tsv
hash()
{
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1"
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
mkdir "$work"
mkdir "$work/archives" "$work/source" "$work/logs"
cp "$manifest" "$work/logs/sources.tsv"
# Verify every archive before extracting any, including pinned submodules.
while read -r archive expected url destination; do
    case "$archive" in ''|'#'*) continue ;; esac
    if [ "$#" -eq 3 ]; then cp "$3/$archive" "$work/archives/$archive"
    else curl -fLsS --connect-timeout 15 --max-time 300 "$url" -o "$work/archives/$archive"; fi
    [ "$(hash "$work/archives/$archive")" = "$expected" ] || {
        echo "Checksum mismatch: $archive; nothing extracted." >&2; exit 2;
    }
done < "$manifest"
while read -r archive expected url destination; do
    case "$archive" in ''|'#'*) continue ;; esac
    mkdir -p "$work/source/$destination"
    tar -xzf "$work/archives/$archive" --strip-components=1 -C "$work/source/$destination"
done < "$manifest"
printf 'Prepared original %s sources: %s/source\n' "$component" "$work"
echo 'This verifies source provenance only; no native build or runtime is claimed.'
