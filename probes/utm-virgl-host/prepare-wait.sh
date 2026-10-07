#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted exact wait-result stage; no installed host changes.
set -eu
[ "$#" -eq 3 ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
archive=$1 inputs=$2 work=$3
hash(){ shasum -a 256 "$1" | awk '{print $1}'; }
[ "$(hash "$recipe/wait-sources.tsv")" = 083d2b4b209955480ca354560813708129018158e507780481105f6a9e45e49e ] || { echo 'Wait manifest mismatch' >&2;exit 1; }
sh "$recipe/prepare-completion.sh" "$archive" "$inputs" "$work"
mkdir "$work/wait-original"
while IFS="$(printf '\t')" read -r kind path sum;do
 case "$kind" in ''|'#'*)continue;;
 original) tar -xzf "$archive" -C "$work/wait-original" --strip-components=1 "utmapp-virglrenderer-5d26f60/$path";[ "$(hash "$work/wait-original/$path")" = "$sum" ] || { echo "Wait original mismatch: $path" >&2;exit 1; };;
 input) [ "$(hash "$work/$path")" = "$sum" ] || { echo "Wait input mismatch: $path" >&2;exit 1; };;
 patch) [ "$(hash "$recipe/$path")" = "$sum" ] || { echo "Wait delta mismatch: $path" >&2;exit 1; };;
 output) :;;
 *) echo "Unknown wait manifest class: $kind" >&2;exit 1;;
 esac
done < "$recipe/wait-sources.tsv"
cp -R "$work/qemu/completion" "$work/qemu/wait"
cp -R "$work/renderer-lifecycle" "$work/renderer-wait"
cp "$work/wait-original/src/vrend/vrend_winsys_egl.c" "$work/wait-original/src/vrend/vrend_winsys_egl.h" "$work/renderer-wait/src/vrend/"
apply(){
 ruby "$recipe/tests/lifecycle-seams.rb" verify-patch "$1" "$2"
 patch -f -F 0 -d "$1" -p1 < "$2" > "$3" 2>&1 || { cat "$3" >&2;exit 1; }
 if grep -Ei 'fuzz|offset|FAILED|Reversed|previously applied|Skipping|malformed' "$3";then echo 'Non-exact wait patch application' >&2;exit 1;fi
}
apply "$work/qemu/wait" "$recipe/patches/wait-qemu-local.patch" "$work/wait-qemu.log"
apply "$work/renderer-wait" "$recipe/patches/wait-renderer-local.patch" "$work/wait-renderer.log"
while IFS="$(printf '\t')" read -r kind path sum;do
 [ "$kind" = output ] || continue
 [ "$(hash "$work/$path")" = "$sum" ] || { echo "Wait output mismatch: $path" >&2;exit 1; }
done < "$recipe/wait-sources.tsv"
find "$work/qemu/wait" "$work/renderer-wait" "$work/wait-original" -type f ! -name '*.orig' ! -name '*.rej' -exec shasum -a 256 {} \; > "$work/wait-prepared-sha256.txt"
printf '%s\n' 'PASS: exact paired wait delta after accepted completion stage; source contract only.'
