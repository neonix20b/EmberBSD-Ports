#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted preparation rejection contracts.
set -eu
export LC_ALL=C
[ "$#" -eq 2 ] || { echo "Usage: $0 ORIGINAL_ARCHIVE NEW_ABSOLUTE_WORK" >&2; exit 2; }
archive=$1
work=$2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$work" in /*) ;; *) exit 2 ;; esac
mkdir "$work"
reject()
{
    label=$1
    message=$2
    shift 2
    if "$@" > "$work/$label.log" 2>&1; then result=0; else result=$?; fi
    printf '%s\n' "$result" > "$work/$label.status"
    [ "$result" -ne 0 ]
    grep -Fq "$message" "$work/$label.log"
    printf 'PASS: %s rejected (status %s)\n' "$label" "$result"
}
for script in "$recipe/prepare.sh" "$recipe/test.sh" "$recipe/tests/guards.sh"; do sh -n "$script"; done
printf '%s\n' 'not the pinned archive' > "$work/wrong.tar.gz"
reject archive 'Original archive SHA256 mismatch' sh "$recipe/prepare.sh" "$work/wrong.tar.gz" "$work/wrong-source"
[ ! -e "$work/wrong-source" ]
reject relative 'Work path must be absolute' sh "$recipe/prepare.sh" "$archive" relative-work
mkdir "$work/existing"
printf '%s\n' 'preserve me' > "$work/existing/sentinel"
reject existing 'File exists' sh "$recipe/prepare.sh" "$archive" "$work/existing"
grep -Fqx 'preserve me' "$work/existing/sentinel"
cp -R "$recipe" "$work/recipe"
printf '\n%s\n' 'tampered' >> "$work/recipe/patches/123e0bc-upstream.patch"
reject patch 'Original upstream patch SHA256 mismatch' sh "$work/recipe/prepare.sh" "$archive" "$work/wrong-patch"
[ ! -e "$work/wrong-patch" ]
printf '%s\n' 'PASS: shell syntax, wrong archive/revision, altered upstream patch, relative/existing work guards.'
