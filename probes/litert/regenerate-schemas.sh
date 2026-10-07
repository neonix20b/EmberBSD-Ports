#!/bin/sh
# SPDX-License-Identifier: MIT
# Regenerate upstream schemas with the single selected FlatBuffers version.
set -eu
[ "$#" = 3 ] || { echo 'Usage: regenerate-schemas.sh FLATC LITERT_SOURCE TENSORFLOW_SOURCE' >&2; exit 2; }
flatc=$1
litert=$2
tensorflow=$3
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
regenerate()
{
    schema=$1
    destination=$2
    name=$(basename "$schema" .fbs)
    "$flatc" --cpp --gen-object-api --gen-compare --no-includes --gen-mutable \
        --reflect-names --cpp-ptr-type flatbuffers::unique_ptr \
        -o "$scratch" "$schema"
    # Preserve the upstream copyright/license preamble of generated headers.
    sed -n '1,/^\/\/ automatically generated/{ /^\/\/ automatically generated/!p; }' \
        "$destination" > "$scratch/notice"
    cat "$scratch/notice" "$scratch/${name}_generated.h" > "$scratch/result.h"
    cmp -s "$scratch/result.h" "$destination" || cp "$scratch/result.h" "$destination"
}
for tree in "$litert/tflite/converter/schema" "$tensorflow/tensorflow/compiler/mlir/lite/schema"; do
    for name in schema conversion_metadata; do
        regenerate "$tree/$name.fbs" "$tree/${name}_generated.h"
    done
done
for tree in "$litert/tflite/acceleration/configuration"; do
    [ -f "$tree/configuration.proto" ] || continue
    "$flatc" --proto -o "$scratch" "$tree/configuration.proto"
    sed 's/tflite.proto/tflite/g' "$scratch/configuration.fbs" > "$scratch/renamed.fbs"
    mv "$scratch/renamed.fbs" "$scratch/configuration.fbs"
    regenerate "$scratch/configuration.fbs" "$tree/configuration_generated.h"
done

# The legacy proto imports the canonical schema; keep its generated C++ view identical.
cmp -s "$litert/tflite/acceleration/configuration/configuration_generated.h" "$litert/tflite/experimental/acceleration/configuration/configuration_generated.h" ||
cp "$litert/tflite/acceleration/configuration/configuration_generated.h" \
    "$litert/tflite/experimental/acceleration/configuration/configuration_generated.h"
