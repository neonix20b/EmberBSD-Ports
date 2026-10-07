#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; target execution of the cross-compiled native test sources.
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: run-target.sh OUTPUT_DIRECTORY' >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ] || {
    echo 'Execute the built tests on AArch64 EmberBSD/NetBSD.' >&2; exit 2;
}
[ -z "${LD_LIBRARY_PATH:-}${LD_PRELOAD:-}" ] || { echo 'Remove loader overrides.' >&2; exit 2; }
out=$(CDPATH= cd -- "$1" && pwd -P)
"$out/atomic-tls"
"$out/atomic-tls-lto"
"$out/boundary" > "$out/loaded.txt"
ldd "$out/boundary" > "$out/ldd.txt"
sh "$out/check-runtime.sh" /usr/pkg/gcc16 "$out"
cat "$out/loaded.txt"
echo 'PASS: cross-built C11/C++20, atomics, threads, TLS, DSO unwind and selected GCC16 runtimes'
