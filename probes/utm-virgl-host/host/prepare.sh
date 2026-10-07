#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted full host renderer preparation; offline and uninstalled.
set -eu
[ "$#" -eq 5 ] || { echo "Usage: $0 RENDERER_ARCHIVE EPOXY_ARCHIVE MESA_ARCHIVE RAW_QEMU_INPUTS NEW_ABSOLUTE_WORK" >&2; exit 2; }
renderer=$1 epoxy=$2 mesa=$3 inputs=$4 work=$5
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "$work" in /*) ;; *) echo 'Work path must be absolute' >&2; exit 2;; esac
hash() { shasum -a 256 "$1" | awk '{print $1}'; }
check() { [ "$(hash "$1")" = "$2" ] || { echo "SHA256 mismatch: $1" >&2; exit 1; }; }
check "$renderer" 6834f45a0b6e904bc8836426657ffcbf13cbc2c2632fb63e6eec57e23670055f
check "$epoxy" a7ced37f4102b745ac86d6a70a9da399cc139ff168ba6b8002b4d8d43c900c15
check "$mesa" bce5f7fbebb934373b86c999a064d52fb5065878dc57f287f95346648ec832e9
check "$recipe/libepoxy-current-angle.patch" 773dc0d45a9d565a829c9dd941de9555c22d8b58fd8a4527b283c227ac4ed93a
check "$recipe/epoxy-files.tsv" 38c1d601a2d0d5748e55cd5164a366ab21d9d79689ccf8e6574e0357cfacc68e
check "$recipe/blitter-null-context.patch" a244fb2a4e77248318bcefee05a47b8ae34a8a2bc1c6c462d8460f3acd8cb8ac
check "$recipe/decoder-truncated-error.patch" c3fba68e356a76e48f8ed83414146b2201fb2b564aff1375d0e3e39f2e2b3683
check "$recipe/renderer-files.tsv" 4a15ee36d551c85c48237ae2ec4c51a003ec89b28af69af7c6ffb2c32159c8ca
check "$recipe/ANGLE-LICENSE" bf4da21bd20bcfb5b60b7ecc67fa864a79be049e21d6178076887f178dd6c71a
mkdir "$work"
sh "$recipe/../prepare-wait.sh" "$renderer" "$inputs" "$work/stages" > "$work/prepare-wait.log" 2>&1 || { cat "$work/prepare-wait.log" >&2; exit 1; }
mkdir "$work/renderer" "$work/epoxy" "$work/khronos"
tar -xzf "$renderer" -C "$work/renderer" --strip-components=1
# The accepted stage contains exact whole files, including unchanged dependencies.
# Never copy patch backup/reject files into the full build tree.
(cd "$work/stages/renderer-wait" && find . -type f ! -name '*.orig' ! -name '*.rej') |
while IFS= read -r path; do
    cp "$work/stages/renderer-wait/$path" "$work/renderer/$path"
done
tar -xzf "$epoxy" -C "$work/epoxy" --strip-components=1
tar -xJf "$mesa" -C "$work/khronos" --strip-components=2 mesa-26.2.4/include/EGL mesa-26.2.4/include/KHR
verify_files() {
    tree=$1 manifest=$2 phase=$3
    while IFS="$(printf '\t')" read -r kind path sum; do
        if [ "$kind" = absent ] && [ "$phase" = input ]; then
            [ ! -e "$tree/$path" ] || { echo "Expected absent: $path" >&2; exit 1; }
        elif [ "$kind" = "$phase" ]; then check "$tree/$path" "$sum"; fi
    done < "$manifest"
}
apply() {
    ruby "$recipe/../tests/lifecycle-seams.rb" verify-patch "$1" "$2"
    patch -f -F 0 -d "$1" -p1 < "$2" > "$3" 2>&1 || { cat "$3" >&2; exit 1; }
    if grep -Ei 'fuzz|offset|FAILED|Reversed|previously applied|Skipping|malformed' "$3"; then
        echo 'Non-exact host patch application' >&2; exit 1
    fi
}
verify_files "$work/epoxy" "$recipe/epoxy-files.tsv" input
# The epoxy patch adds two registry files, so its new-file hunks use /dev/null.
patch -f -F 0 -d "$work/epoxy" -p1 < "$recipe/libepoxy-current-angle.patch" > "$work/epoxy-patch.log" 2>&1 || { cat "$work/epoxy-patch.log" >&2; exit 1; }
if grep -Ei 'fuzz|offset|FAILED|Reversed|previously applied|Skipping|malformed' "$work/epoxy-patch.log"; then exit 1; fi
verify_files "$work/epoxy" "$recipe/epoxy-files.tsv" output
cp "$recipe/ANGLE-LICENSE" "$work/epoxy/ANGLE-LICENSE"
verify_files "$work/renderer" "$recipe/renderer-files.tsv" input
apply "$work/renderer" "$recipe/blitter-null-context.patch" "$work/blitter-patch.log"
apply "$work/renderer" "$recipe/decoder-truncated-error.patch" "$work/decoder-patch.log"
verify_files "$work/renderer" "$recipe/renderer-files.tsv" output
(cd "$work" && find renderer epoxy khronos -type f ! -name '*.orig' ! -name '*.rej' -exec shasum -a 256 {} \;) > "$work/source-sha256.txt"
printf '%s\n' 'PASS: full renderer and libepoxy 1.5.10 prepared; no build or installed host changes.'
