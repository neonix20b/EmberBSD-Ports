#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted full QEMU preparation after the accepted source contracts.
set -eu
[ "$#" -eq 4 ] || { echo "Usage: $0 QEMU_ARCHIVE RENDERER_ARCHIVE RAW_INPUTS NEW_ABSOLUTE_WORK" >&2; exit 2; }
archive=$1 renderer=$2 inputs=$3 work=$4
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "$work" in /*) ;; *) exit 2;; esac
hash() { shasum -a 256 "$1" | awk '{print $1}'; }
[ "$(hash "$archive")" = 7c9605290b34152debb842e965a55d2e4fbba4793e536ab677b4027e5dc0ba1a ] || { echo 'QEMU archive mismatch' >&2; exit 1; }
[ "$(hash "$inputs/utm-v5.0.6-qemu.patch")" = 05a46d5e52fd662e8d40bd28d23c0cf702f92cc28a83eca89e9ee14c1646aee7 ] || { echo 'UTM overlay mismatch' >&2; exit 1; }
mkdir "$work"
sh "$recipe/../prepare-wait.sh" "$renderer" "$inputs" "$work/stages" > "$work/source-stage.log" 2>&1 || { cat "$work/source-stage.log" >&2; exit 1; }
mkdir "$work/src"
tar -xJf "$archive" -C "$work/src" --strip-components=1
# Check the release archive against the original files used by the source tests.
while IFS="$(printf '\t')" read -r name revision url sum; do
    case "$name" in ''|'#'*|utm-v5.0.6-qemu.patch) continue;; esac
    path=${url#*"/$revision/"}
    [ "$(hash "$work/src/$path")" = "$sum" ] || { echo "QEMU original mismatch: $path" >&2; exit 1; }
done < "$recipe/../create-sources.tsv"
# Apply every UTM section to the complete source tree, including UI/SPICE/Cocoa.
patch -f -F 0 -d "$work/src" -p1 < "$inputs/utm-v5.0.6-qemu.patch" > "$work/utm-overlay.log" 2>&1 || { cat "$work/utm-overlay.log" >&2; exit 1; }
if grep -Ei 'fuzz|offset|FAILED|Reversed|previously applied|Skipping|malformed' "$work/utm-overlay.log"; then exit 1; fi
(cd "$work/stages/qemu/post-overlay" && find . -type f ! -name '*.orig' ! -name '*.rej') |
while IFS= read -r path; do
    cmp "$work/stages/qemu/post-overlay/$path" "$work/src/$path"
done
# These exact whole files contain all accepted local stages; other files retain
# the full UTM overlay. No derived patch is re-applied to already patched code.
(cd "$work/stages/qemu/wait" && find . -type f ! -name '*.orig' ! -name '*.rej') |
while IFS= read -r path; do cp "$work/stages/qemu/wait/$path" "$work/src/$path"; done
(cd "$work" && find src -type f ! -name '*.orig' ! -name '*.rej' -exec shasum -a 256 {} +) > "$work/source-sha256.txt"
printf '%s\n' 'PASS: full QEMU tree with complete UTM overlay and accepted paired source.'
