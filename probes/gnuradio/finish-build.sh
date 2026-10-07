#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: finish-build.sh ABS_CONFIGURED_WORK' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple path.' >&2; exit 2 ;; esac
[ -f "$work/gnuradio-build/build.ninja" ] && [ -f "$work/logs/sources.txt" ] || {
    echo 'Missing configured source build.' >&2; exit 2;
}
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || exit 2
build_as_kib=${BUILD_AS_KIB:-1572864}
case "$build_as_kib" in ''|0|*[!0-9]*) echo 'BUILD_AS_KIB must be positive.' >&2; exit 2 ;; esac
ulimit -v "$build_as_kib"
printf 'BUILD_AS_KIB=%s\n' "$build_as_kib" > "$work/logs/build-limits.txt"
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
cmake=${CMAKE:-cmake}
prefix=$work/install
run()
{
    stage=$1
    shift
    printf '%s\n' "$stage"
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        tail -70 "$work/logs/$stage.log" >&2
        exit "$status"
    fi
}
run gnuradio-build "$cmake" --build "$work/gnuradio-build" --parallel "$jobs"
run gnuradio-install "$cmake" --install "$work/gnuradio-build"
mkdir -p "$prefix/share/ember-gnuradio/licenses"
cp "$recipe/sources.tsv" "$recipe/patches.tsv" "$recipe/PROVENANCE.md" "$prefix/share/ember-gnuradio/"
cp "$work/src/gnuradio-3.10.12.0/COPYING" "$prefix/share/ember-gnuradio/licenses/GNU-Radio-GPL-3.0"
cp "$work/src/spdlog-1.17.0/LICENSE" "$prefix/share/ember-gnuradio/licenses/spdlog-MIT"
echo "Installed in $prefix; run test.sh next."
