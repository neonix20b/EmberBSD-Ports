#!/bin/sh
# SPDX-License-Identifier: MIT
# Portable source/input guards; no compilation or target OS is required.
set -eu
[ "$#" = 1 ] || { echo 'Usage: build-guards.sh ABS_SCRATCH_PARENT' >&2; exit 2; }
case "$1" in /*) ;; *) exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "$1/probe-guards.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
mkdir "$scratch/cache" "$scratch/existing"
printf 'preserve\n' > "$scratch/existing/sentinel"
if sh "$recipe/build.sh" "$scratch/existing" > "$scratch/existing.log" 2>&1; then exit 1; fi
grep -q 'Work path already exists' "$scratch/existing.log"
[ "$(cat "$scratch/existing/sentinel")" = preserve ]
if JOBS=0 sh "$recipe/build.sh" "$scratch/jobs" > "$scratch/jobs.log" 2>&1; then exit 1; fi
grep -q 'JOBS must be positive' "$scratch/jobs.log"
[ ! -e "$scratch/jobs" ]
if EIGEN_PREFIX="$scratch/missing-eigen" sh "$recipe/build.sh" "$scratch/external" > "$scratch/external.log" 2>&1; then exit 1; fi
grep -q 'Common Eigen 5.0.1 required' "$scratch/external.log"
[ ! -e "$scratch/external" ]
while read -r name expected url; do printf 'corrupt\n' > "$scratch/cache/$name"; done < "$recipe/sources.tsv"
if sh "$recipe/build.sh" "$scratch/corrupt" "$scratch/cache" > "$scratch/corrupt.log" 2>&1; then exit 1; fi
grep -q 'Checksum mismatch' "$scratch/corrupt.log"
[ -z "$(ls -A "$scratch/corrupt/src")" ]
echo 'PASS existing work, zero jobs, and corrupt archive rejected before extraction'
