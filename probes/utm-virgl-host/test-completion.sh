#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted causal actual-body reported status checks.
set -eu
[ "$#" -eq 3 ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$3
sh "$recipe/prepare-completion.sh" "$1" "$2" "$work"
"${CC:-cc}" --version > "$work/completion-compiler.txt"
uname -a > "$work/completion-platform.txt"
for version in baseline patched;do
 out=$work/test-$version
 sh "$recipe/tests/extract-completion.sh" "$work" "$out" "$version"
 for mode in plain sanitized release;do
  set --
  case "$mode" in sanitized) set -- -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer;;release) set -- -DNDEBUG;;esac
  "${CC:-cc}" -std=gnu11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-variable -Wno-unused-parameter -Wno-unused-but-set-variable -Wno-sign-compare -Wno-missing-field-initializers "$@" -I"$out" -I"$work/renderer-lifecycle/src" "$out/completion.c" -o "$out/$mode" > "$out/$mode-compile.log" 2>&1 || { cat "$out/$mode-compile.log" >&2;exit 1; }
  if "$out/$mode" > "$out/$mode.log" 2>&1;then status=0;else status=$?;fi
  printf '%s\n' "$status" > "$out/$mode.status"
  if [ "$version" = baseline ];then
   [ "$status" -eq 1 ] && grep -Fq 'FAIL reported command error retains cmdq ownership before revoke' "$out/$mode.log" && grep -Fq 'FAIL fence failure retains command without fictitious inflight or OK' "$out/$mode.log" || { cat "$out/$mode.log" >&2;exit 1; }
  else
   [ "$status" -eq 0 ] && grep -Fq '683 checks, 0 failures' "$out/$mode.log" || { cat "$out/$mode.log" >&2;exit 1; }
  fi
  if grep -E 'ERROR: AddressSanitizer|runtime error:|LeakSanitizer' "$out/$mode.log";then exit 1;fi
  tail -1 "$out/$mode.log"
 done
done
printf '%s\n' 'PASS: actual reported command/fence status RED/GREEN in plain, ASan/UBSan and NDEBUG; backend detection/native qualification remains open.'
