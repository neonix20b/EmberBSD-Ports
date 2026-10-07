#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" -ge 1 ] && [ "$#" -le 3 ] || {
    echo 'Usage: test.sh PREFIX [LITERT_LM_SOURCE [TRAINED_MODEL]]' >&2; exit 2;
}
[ "$(uname -s)" = NetBSD ] || { echo 'Run acceptance on the NetBSD target.' >&2; exit 2; }
prefix=$1
# Installed consumers use their relative runtime search path.
"$prefix/libexec/ember-litert/ember-litert-runtime-c" "$prefix/share/ember-litert/runtime-add.tflite"
"$prefix/libexec/ember-litert/ember-litert-runtime-cpp" "$prefix/share/ember-litert/runtime-add.tflite"
"$prefix/bin/ember-gated-delta-test"
"$prefix/bin/ember-task-metadata-test" "$prefix/share/ember-litert/task-state.tflite"
if [ "$#" -ge 2 ]; then
    recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
    sh "$recipe/../litert-lm/test.sh" "$prefix/bin/ember-litert-lm" "$2"
fi
if [ "$#" = 3 ]; then
    "$prefix/bin/ember-litert-lm" verify "$3" 'The capital of France is' 16 2
fi
