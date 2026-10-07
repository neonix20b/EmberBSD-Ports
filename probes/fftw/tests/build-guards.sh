#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
recipe=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/ember-fftw-guards.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
mkdir "$scratch/existing" "$scratch/cache"
printf 'preserve\n' > "$scratch/existing/sentinel"
if sh "$recipe/build.sh" "$scratch/existing" "$scratch/cache" > "$scratch/existing.log" 2>&1; then
    echo 'Existing work path accepted.' >&2; exit 1
fi
grep -F 'Work path already exists.' "$scratch/existing.log" >/dev/null
grep -F 'preserve' "$scratch/existing/sentinel" >/dev/null
for jobs in 0 -1 wrong; do
    if JOBS=$jobs sh "$recipe/build.sh" "$scratch/jobs-$jobs" "$scratch/cache" > "$scratch/jobs.log" 2>&1; then
        echo 'Invalid JOBS accepted.' >&2; exit 1
    fi
    [ ! -e "$scratch/jobs-$jobs" ]
done
if sh "$recipe/build.sh" relative "$scratch/cache" > "$scratch/relative.log" 2>&1; then
    echo 'Relative work path accepted.' >&2; exit 1
fi
# Corruption in the first source must fail before any archive is extracted.
read -r first expected url < "$recipe/sources.tsv"
printf 'not a source archive\n' > "$scratch/cache/$first"
if sh "$recipe/build.sh" "$scratch/corrupt" "$scratch/cache" > "$scratch/corrupt.log" 2>&1; then
    echo 'Corrupt archive accepted.' >&2; exit 1
fi
grep -F "Checksum mismatch: $first" "$scratch/corrupt.log" >/dev/null
[ -d "$scratch/corrupt/src" ]
set -- "$scratch/corrupt/src/"*
[ ! -e "$1" ]
echo 'Build guards: existing work, invalid JOBS, relative path and corrupt archive passed.'
