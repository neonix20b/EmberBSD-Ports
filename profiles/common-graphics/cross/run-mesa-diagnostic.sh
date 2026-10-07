#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; target execution of a private Mesa diagnostic bundle.
set -eu
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ] || {
    echo 'Run on EmberBSD/NetBSD AArch64' >&2; exit 2
}
[ "$#" -eq 2 ] || {
    echo 'Usage: run-mesa-diagnostic.sh surfaceless|RENDER_NODE EXPECTED_RENDERER' >&2
    exit 2
}
cd -- "$(dirname -- "$0")"
bundle=$(pwd -P)
timeout=${TIMEOUT:-/usr/bin/timeout}
[ -x "$timeout" ] || { echo 'A target timeout executable is required' >&2; exit 2; }
unset LD_PRELOAD MESA_LOADER_DRIVER_OVERRIDE LIBGL_ALWAYS_SOFTWARE
export LD_LIBRARY_PATH=$bundle/lib
export LIBGL_DRIVERS_PATH=$bundle/lib/dri
export GBM_BACKENDS_PATH=$bundle/lib/gbm
export MESA_SHADER_CACHE_DISABLE=true
mkdir -p logs
# Check the exact transferred artifacts before resolving their dependencies.
while read -r expected file; do
    [ -f "$file" ] && [ "$(sha256 -q "$file")" = "$expected" ] || {
        echo "Artifact checksum mismatch: $file" >&2; exit 1
    }
done < artifacts.sha256
for file in ./mesa-render ./lib/*.so* ./lib/dri/*.so ./lib/gbm/*.so; do
    [ -f "$file" ] || continue
    ldd "$file" > logs/ldd-last.txt
    cat logs/ldd-last.txt >> logs/loader.txt
    awk '$2 == "=>" && $3 !~ /^\// { bad=1 } END { exit bad }' logs/ldd-last.txt || {
        echo "Unresolved dependency: $file" >&2; exit 1
    }
    awk '$2 == "=>" { print $3 }' logs/ldd-last.txt |
    while read -r path; do
        case "$path" in
            */libEGL.so*|*/libGLES*.so*|*/libgbm.so*|*/libgallium*|*/libdrm.so*|\
            */libstdc++.so*|*/libgcc_s.so*|*/libzstd.so*)
                resolved=$(realpath "$path")
                case "$resolved" in "$bundle"/lib/*) ;;
                    *) echo "Foreign diagnostic dependency: $resolved" >&2; exit 1;;
                esac
                ;;
            */libglapi.so*|*/libLLVM*|*/libGL.so*)
                echo "Unexpected diagnostic dependency: $path" >&2; exit 1;;
        esac
    done
done
uname -a
"$timeout" 60 ./mesa-render "$1" "$2"
echo 'PASS: private Mesa render diagnostic; not common package or LLVM acceptance'
