#!/bin/sh
# Run small regression checks with the same C++ runtime as the system Qt.
set -eu
recipe_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir=${KWIN_SOURCE_DIR:?Set KWIN_SOURCE_DIR to the patched KWin source}
PATH=/usr/pkg/bin:/usr/pkg/qt6/bin:/bin:/usr/bin
export PATH
scratch=$(mktemp -d "${TMPDIR:-/tmp}/kwin-portability.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
# pkg-config emits compiler arguments, so its output is intentionally split.
${CXX:-/usr/bin/c++} -std=c++23 -fPIC -I"$source_dir/src" \
    $(pkg-config --cflags Qt6Core) "$recipe_dir/scripts/ranges-probe.cpp" \
    -o "$scratch/ranges-probe" $(pkg-config --libs Qt6Core) \
    -Wl,--no-undefined -Wl,--fatal-warnings
"$scratch/ranges-probe"
ldd "$scratch/ranges-probe"
${CC:-/usr/bin/cc} "$recipe_dir/scripts/sysctl-path-probe.c" -o "$scratch/sysctl-path-probe"
"$scratch/sysctl-path-probe"
