#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted finite causal gate. No host activation/full build.
set -eu
[ "$#" -eq 3 ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$3
sh "$recipe/prepare-lifecycle.sh" "$1" "$2" "$work"
"${CC:-cc}" --version > "$work/lifecycle-compiler.txt"
uname -a > "$work/lifecycle-platform.txt"
extract() { sh "$recipe/tests/extract-lifecycle.sh" "$1" "$work" "$work/$2" "${3:-patched}"; }
extract qemu test-qemu
extract reset test-reset-red
extract renderer test-renderer
extract renderer test-renderer-red baseline
extract backing test-backing
compile() {
 out=$1; mode=$2; source=$3;shift 3
 if [ "$mode" = sanitized ];then set -- "$@" -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer;fi
 if [ "$mode" = release ];then set -- "$@" -DNDEBUG;fi
 "${CC:-cc}" -std=gnu11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-variable -Wno-unused-parameter -Wno-unused-but-set-variable -Wno-sign-compare "$@" -I"$out" -I"$work/renderer-lifecycle/src" -I"$work/renderer-lifecycle/src/vrend" "$source" -o "$out/$mode" > "$out/$mode-compile.log" 2>&1 || { cat "$out/$mode-compile.log" >&2;exit 1; }
}
run() {
 out=$1; mode=$2; expected=$3; pattern=$4
 if "$out/$mode" > "$out/$mode.log" 2>&1;then status=0;else status=$?;fi
 printf '%s\n' "$status" > "$out/$mode.status"
 [ "$status" -eq "$expected" ] || { cat "$out/$mode.log" >&2;echo "Unexpected $out/$mode: $status" >&2;exit 1; }
 grep -Fq "$pattern" "$out/$mode.log" || { cat "$out/$mode.log" >&2;exit 1; }
 if grep -E 'ERROR: AddressSanitizer|runtime error:|LeakSanitizer' "$out/$mode.log";then exit 1;fi
 tail -1 "$out/$mode.log"
}
for mode in plain sanitized release;do
 compile "$work/test-reset-red" "$mode" "$recipe/tests/lifecycle.c" -DLIFECYCLE_BASELINE_RESET
 run "$work/test-reset-red" "$mode" 1 'FAIL release before final detach'
 compile "$work/test-renderer-red" "$mode" "$recipe/tests/lifecycle.c" -DLIFECYCLE_RENDERER -DBASELINE
 run "$work/test-renderer-red" "$mode" 1 'FAIL empty-fence poll completes pending query'
 grep -Fq 'FAIL external EGL cleanup owns wrapper and GBM, never display' "$work/test-renderer-red/$mode.log"
 compile "$work/test-qemu" "$mode" "$recipe/tests/lifecycle.c"
 run "$work/test-qemu" "$mode" 0 '86 checks, 0 failures'
 for config in normal gbm video;do
  out=$work/renderer-$config
  if [ ! -d "$out" ];then mkdir "$out";cp "$work/test-renderer/"*.inc "$work/test-renderer/virgl-version.h" "$out/";fi
  set -- -DLIFECYCLE_RENDERER
  case "$config" in gbm) set -- "$@" -DENABLE_GBM;;video) set -- "$@" -DENABLE_VIDEO;;esac
  compile "$out" "$mode" "$recipe/tests/lifecycle.c" "$@"
  run "$out" "$mode" 0 '0 failures'
 done
 compile "$work/test-backing" "$mode" "$work/test-backing/backing.c" -DVIRGL_VERSION_MAJOR=1 -DBACKING_PATCHED "$work/renderer-lifecycle/src/vrend/iov.c"
 run "$work/test-backing" "$mode" 0 '4 checks, 0 failures'
done
compile "$work/test-qemu" no-abi "$recipe/tests/lifecycle.c" -DLIFECYCLE_NO_ABI
export LIFECYCLE_NO_ABI=1
run "$work/test-qemu" no-abi 0 'old ABI rejected'
unset LIFECYCLE_NO_ABI
for mutant in release-per-resource lost-oom-latch stale-generation thread-sync command-guard display-handoff fault-handoff cleanup-under-block reset-response poll-no-rearm producer-poll-gate resource-precheck blocked-unrealize callback-defaults skip-second-detach;do
 out=$work/mutant-$mutant
 mkdir "$out";cp "$work/test-qemu/"*.inc "$work/test-qemu/virgl-version.h" "$out/"
 ruby "$recipe/tests/lifecycle-seams.rb" mutate "$out/functions.inc" "$mutant"
 for mode in plain sanitized release;do
  compile "$out" "$mode" "$recipe/tests/lifecycle.c"
  if [ "$mutant" = skip-second-detach ];then export LIFECYCLE_ORDER_CHILD=1;fi
  run "$out" "$mode" 1 'FAIL '
  unset LIFECYCLE_ORDER_CHILD
 done
 printf 'CAUSAL: %s rejected in plain/ASan+UBSan/NDEBUG\n' "$mutant"
done
for mutant in early-query-return external-cleanup-gbm-guard;do
 out=$work/mutant-$mutant
 mkdir "$out";cp "$work/test-renderer/"*.inc "$work/test-renderer/virgl-version.h" "$out/"
 if [ "$mutant" = early-query-return ];then
  ruby "$recipe/tests/lifecycle-seams.rb" mutate "$out/renderer-functions.inc" "$mutant"
 else
  # Restore only the complete former winsys cleanup, not query/ABI changes.
  awk -v name=virgl_egl_init_external -f "$recipe/tests/extract-lifecycle.awk" "$work/renderer-extra-original/src/vrend/vrend_winsys_egl.c" > "$out/winsys-functions.inc"
  for name in vrend_winsys_init_external vrend_winsys_cleanup;do awk -v name="$name" -f "$recipe/tests/extract-lifecycle.awk" "$work/renderer-extra-original/src/vrend/vrend_winsys.c" >> "$out/winsys-functions.inc";done
 fi
 for mode in plain sanitized release;do
  compile "$out" "$mode" "$recipe/tests/lifecycle.c" -DLIFECYCLE_RENDERER
  run "$out" "$mode" 1 'FAIL '
 done
 printf 'CAUSAL: %s rejected in plain/ASan+UBSan/NDEBUG\n' "$mutant"
done
printf '%s\n' 'PASS: bounded actual-body lifecycle suite; scheduler/DMA/display/GL seams remain native gates.'
