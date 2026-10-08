#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted). Run on the target after staging full LLVM.
set -eu
[ "$#" -eq 2 ] || { echo 'usage: record-llvm-config.sh TARGET_LLVM_CONFIG NEW_OUTPUT' >&2; exit 1; }
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ] || {
    echo 'capture must execute on the NetBSD/AArch64 target' >&2
    exit 1
}
llvm_config=$1
output=$2
case "$llvm_config:$output" in /*:/*) ;; *) echo 'absolute paths required' >&2; exit 1;; esac
[ -x "$llvm_config" ] && [ ! -e "$output" ] || { echo 'executable missing or output exists' >&2; exit 1; }
mkdir "$output"
uname -a > "$output/platform"
sha256 -q "$llvm_config" > "$output/executable.sha256"
for option in version host-target has-rtti assertion-mode targets-built components prefix cppflags cflags cxxflags ldflags; do
    "$llvm_config" "--$option" > "$output/$option"
done
for option in shared-mode libs libnames libfiles system-libs; do
    "$llvm_config" --link-shared "--$option" bitwriter engine mcdisassembler mcjit core executionengine scalaropts transformutils instcombine native orcjit > "$output/$option"
done
printf '%s\n' "$llvm_config" > "$output/executable"
printf '%s\n' 'complete' > "$output/status"
