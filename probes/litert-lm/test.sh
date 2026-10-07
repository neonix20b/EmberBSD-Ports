#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 /path/to/ember-litert-lm /path/to/LiteRT-LM-0.18.0" >&2
    exit 2
fi
cli=$1
source_dir=$2
fixture=$source_dir/runtime/testdata/test_lm.litertlm
expected=36c6cc10f140e5e3526c0838ebb5ce74142b3c0ce8d1356c7d6d0ff50de6a288
if command -v sha256 >/dev/null 2>&1; then
    actual=$(sha256 -q "$fixture")
elif command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$fixture" | cut -d ' ' -f 1)
else
    actual=$(shasum -a 256 "$fixture" | cut -d ' ' -f 1)
fi
[ "$actual" = "$expected" ] || { echo "Fixture checksum mismatch" >&2; exit 1; }
scratch=$(mktemp -d "${TMPDIR:-/tmp}/ember-litert-lm.XXXXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
printf '%s\n' 'This is not a LiteRT-LM model.' > "$scratch/malformed.litertlm"
"$cli" reject "$scratch/missing.litertlm"
"$cli" reject "$scratch/malformed.litertlm"
"$cli" verify "$fixture" 'Hello world!' 8 2
