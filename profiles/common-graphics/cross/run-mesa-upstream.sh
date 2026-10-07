#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; bounded target execution of upstream Mesa tests.
set -eu
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ] || {
  echo 'Run on EmberBSD/NetBSD AArch64' >&2; exit 2
}
cd -- "$(dirname -- "$0")"
bundle=$(pwd -P)
while read -r expected file; do
  [ -f "$file" ] && [ "$(sha256 -q "$file")" = "$expected" ] || {
    echo "Artifact checksum mismatch: $file" >&2; exit 1
  }
done < artifacts.sha256
export LD_LIBRARY_PATH=$bundle/lib
unset LD_PRELOAD
mkdir -p upstream-logs
failures=0
while IFS="$(printf '\t')" read -r name executable; do
  ldd "$bundle/tests/$executable" > "upstream-logs/$name.ldd"
  if ! awk '$2 == "=>" && $3 !~ /^\// { bad=1 } END { exit bad }' "upstream-logs/$name.ldd"; then
    echo "FAIL $name unresolved dependency"
    failures=$((failures + 1))
    continue
  fi
  awk '$2 == "=>" { print $3 }' "upstream-logs/$name.ldd" |
  while read -r path; do
    case "$path" in */libstdc++.so*|*/libgcc_s.so*|*/libzstd.so*|*/libdrm.so*|*/libgallium*|*/libgbm.so*)
      case "$(realpath "$path")" in "$bundle"/lib/*) ;;
        *) echo "Foreign dependency: $path" >&2; exit 1;;
      esac;;
    esac
  done
  status=0
  (
    export BUILD_FULL_PATH=$bundle/tests/$executable
    unset MESA_PROCESS_NAME
    if [ "$name" = process_with_overrides ]; then export MESA_PROCESS_NAME=hello; fi
    if [ "$name" = xmlconfig ]; then
      export DRIRC_CONFIGDIR=$bundle/fixtures/drirc_configdir
    fi
    /usr/bin/timeout 120 "$bundle/tests/$executable"
  ) > "upstream-logs/$name.log" 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then
    echo "PASS $name"
  elif [ "$status" -eq 77 ]; then
    echo "SKIP $name (exit 77)"
  else
    echo "FAIL $name (exit $status)"
    failures=$((failures + 1))
  fi
done < upstream-tests.tsv
[ "$failures" -eq 0 ]
