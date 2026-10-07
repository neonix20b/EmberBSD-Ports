#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted exact reported-status stage; no host activation.
set -eu
[ "$#" -eq 3 ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$3
hash() { shasum -a 256 "$1" | awk '{print $1}'; }
[ "$(hash "$recipe/completion-sources.tsv")" = ac79d1f3d312337c9cb540fca3ecd0c36e81ddbe5b73d1b2df21878a0e004846 ] || { echo 'Completion manifest mismatch' >&2;exit 1; }
sh "$recipe/prepare-lifecycle.sh" "$1" "$2" "$work"
while IFS="$(printf '\t')" read -r kind path sum;do
 case "$kind" in ''|'#'*)continue;;
 input) [ "$(hash "$work/$path")" = "$sum" ] || { echo "Completion input mismatch: $path" >&2;exit 1; };;
 patch) [ "$(hash "$recipe/$path")" = "$sum" ] || { echo "Completion delta mismatch: $path" >&2;exit 1; };;
 output) :;;
 *) echo "Unknown completion manifest class: $kind" >&2;exit 1;;
 esac
done < "$recipe/completion-sources.tsv"
cp -R "$work/qemu/lifecycle" "$work/qemu/completion"
delta=$recipe/patches/completion-qemu-local.patch
ruby "$recipe/tests/lifecycle-seams.rb" verify-patch "$work/qemu/completion" "$delta"
patch -f -F 0 -d "$work/qemu/completion" -p1 < "$delta" > "$work/completion-qemu.log" 2>&1 || { cat "$work/completion-qemu.log" >&2;exit 1; }
if grep -Ei 'fuzz|offset|FAILED|Reversed|previously applied|Skipping|malformed' "$work/completion-qemu.log";then echo 'Non-exact completion patch application' >&2;exit 1;fi
while IFS="$(printf '\t')" read -r kind path sum;do
 [ "$kind" = output ] || continue
 [ "$(hash "$work/$path")" = "$sum" ] || { echo "Completion output mismatch: $path" >&2;exit 1; }
done < "$recipe/completion-sources.tsv"
find "$work/qemu/completion" -type f ! -name '*.orig' ! -name '*.rej' -exec shasum -a 256 {} \; > "$work/completion-prepared-sha256.txt"
printf '%s\n' 'PASS: reported status delta after accepted lifecycle stage; source contract only.'
