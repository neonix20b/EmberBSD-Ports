#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted actual wait-to-revoke causal tests.
set -eu
[ "$#" -eq 3 ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$3
sh "$recipe/prepare-wait.sh" "$1" "$2" "$work"
"${CC:-cc}" --version > "$work/wait-compiler.txt"
uname -a > "$work/wait-platform.txt"
compile(){
 out=$1 mode=$2 kind=$3;shift 3
 case "$mode" in sanitized)set -- "$@" -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer;;release)set -- "$@" -DNDEBUG;;esac
 "${CC:-cc}" -std=gnu11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-variable -Wno-unused-parameter -Wno-unused-but-set-variable -Wno-sign-compare -Wno-missing-field-initializers "$@" -I"$out" "$out/wait-$kind.c" -o "$out/$mode" > "$out/$mode-compile.log" 2>&1 || { cat "$out/$mode-compile.log" >&2;exit 1; }
}
run(){
 out=$1 mode=$2 expected=$3 pattern=$4
 if "$out/$mode" > "$out/$mode.log" 2>&1;then status=0;else status=$?;fi
 printf '%s\n' "$status" > "$out/$mode.status"
 [ "$status" -eq "$expected" ] && grep -Fq "$pattern" "$out/$mode.log" || { cat "$out/$mode.log" >&2;exit 1; }
 if grep -E 'ERROR: AddressSanitizer|runtime error:|LeakSanitizer' "$out/$mode.log";then exit 1;fi
 tail -1 "$out/$mode.log"
}
for variant in baseline patched;do
 for kind in renderer qemu;do
  out=$work/$kind-$variant
  sh "$recipe/tests/extract-wait-$kind.sh" "$work" "$out" "$variant"
  find "$out" -type f ! -name '*sha256.txt' -exec shasum -a 256 {} \; > "$out/wait-extracted-sha256.txt"
  for mode in plain sanitized release;do
   set --
   [ "$variant" = baseline ] || set -- -DWAIT_PATCHED
   compile "$out" "$mode" "$kind" "$@"
   if [ "$variant" = baseline ];then
    if [ "$kind" = renderer ];then pattern='FAIL failed wait never produces successful completion';else pattern='FAIL actual failed wait reaches QEMU fault before response or ownership loss';fi
    run "$out" "$mode" 1 "$pattern"
   else
    run "$out" "$mode" 0 '0 failures'
   fi
  done
 done
done
compile "$work/qemu-patched" no-abi qemu -DWAIT_PATCHED -DWAIT_NO_ABI
run "$work/qemu-patched" no-abi 0 '2 checks, 0 failures'
printf '%s\n' 'PASS: complete wait bodies and QEMU revoke integration RED/GREEN, plain/ASan+UBSan/NDEBUG; old ABI rejected.'
