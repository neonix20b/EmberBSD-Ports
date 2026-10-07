#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted causal check of the production fini function.
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 PREPARED_WORK NEW_ABSOLUTE_TEST_WORK" >&2; exit 2; }
work=$1 out=$2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "$out" in /*) ;; *) exit 2;; esac
CC=${CC:-cc}
hash() { shasum -a 256 "$1" | awk '{print $1}'; }
base=$work/stages/renderer-extra-original/src/vrend/vrend_blitter.c
fixed=$work/renderer/src/vrend/vrend_blitter.c
[ "$(hash "$base")" = 06521a4bc1320a2e6e02d553fb8d02361c18c22a6b348247999810e7aa31dfb3 ]
expected=$(awk -F '\t' '$1=="output" && $2=="src/vrend/vrend_blitter.c" {print $3; n++} END {if (n != 1) exit 1}' "$recipe/renderer-files.tsv")
[ "$(hash "$fixed")" = "$expected" ]
mkdir "$out"
for variant in baseline patched; do
    source=$base
    [ "$variant" != patched ] || source=$fixed
    cat "$recipe/blitter-seam.h" > "$out/$variant.c"
    ruby -e 's=File.read(ARGV[0]); a=s.scan(/^void vrend_blitter_fini\(void\)\n\{\n.*?^\}\n/m); abort "ambiguous/truncated fini" unless a.size==1; print a[0]' "$source" >> "$out/$variant.c"
    cat "$recipe/blitter-cases.h" >> "$out/$variant.c"
    for mode in plain sanitize; do
        set --
        [ "$mode" != sanitize ] || set -- -fsanitize=address,undefined -fno-omit-frame-pointer
        "$CC" -std=c11 -Wall -Wextra -Werror "$@" "$out/$variant.c" -o "$out/$variant-$mode"
        status=0
        "$out/$variant-$mode" > "$out/$variant-$mode.log" 2>&1 || status=$?
        cat "$out/$variant-$mode.log"
        expected_status=1
        [ "$variant" != patched ] || expected_status=0
        [ "$status" -eq "$expected_status" ] || { echo 'Unexpected contract result' >&2; exit 1; }
        if [ "$variant" = baseline ]; then grep -q '8 checks, 4 failures' "$out/$variant-$mode.log";
        else grep -q '6 checks, 0 failures' "$out/$variant-$mode.log"; fi
        if grep -Eq 'runtime error:|ERROR: AddressSanitizer' "$out/$variant-$mode.log"; then exit 1; fi
    done
done
printf '%s\n' 'PASS: compiled baseline rejects null destroy; patched preserves owned cleanup.'
