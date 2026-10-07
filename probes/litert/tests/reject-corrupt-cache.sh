#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
recipe=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
printf 'not an upstream archive\n' > "$work/litert-v2.2.0.tar.gz"
if sh "$recipe/fetch.sh" "$work" > "$work/output" 2>&1; then
    echo 'FAIL: corrupt cached archive accepted' >&2
    exit 1
fi
grep -q 'Checksum mismatch: litert-v2.2.0' "$work/output"
[ ! -d "$work/src" ]
echo 'PASS: corrupted source cache rejected before extraction'
