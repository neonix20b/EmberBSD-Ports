#!/bin/sh
# SPDX-License-Identifier: MIT
# Migrate only the metadata of a checksum-pinned MediaPipe task bundle.
set -eu
[ "$#" = 4 ] || {
    echo 'Usage: prepare-model.sh tinyllama BUILD_WORK INPUT.task OUTPUT.task' >&2
    exit 2
}
model=$1
work=$2
input=$3
output=$4
case "$model" in tinyllama) ;; *) echo 'Unknown model.' >&2; exit 2 ;; esac
case "$output" in /*) ;; *) echo 'Use an absolute output path.' >&2; exit 2 ;; esac
[ ! -e "$output" ] || { echo 'Output already exists; refusing to replace it.' >&2; exit 2; }
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
protoc=$work/host-build/protobuf/protoc
source_dir=$work/src/LiteRT-LM-0.18.0
[ -x "$protoc" ] && [ -f "$source_dir/runtime/proto/llm_metadata.proto" ] || {
    echo 'Use the completed LiteRT build work directory.' >&2; exit 2;
}
for tool in unzip zip; do
    command -v "$tool" >/dev/null || { echo "Missing host tool: $tool" >&2; exit 2; }
done
checksum()
{
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1"
    else shasum -a 256 "$1" | cut -d ' ' -f 1; fi
}
expected=$(awk -v model="$model" '$1 == model {print $2}' "$recipe/models.tsv")
[ -n "$expected" ] && [ "$(checksum "$input")" = "$expected" ] || {
    echo 'Input model checksum mismatch.' >&2; exit 1;
}
scratch=$(mktemp -d "$(dirname "$output")/.ember-litert-model.XXXXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
# Current LiteRT-LM removed the legacy MediaPipe LlmParameters parser.
"$protoc" "--proto_path=$source_dir" --encode=litert.lm.proto.LlmMetadata \
    runtime/proto/llm_metadata.proto < "$recipe/model-metadata/$model.textproto" \
    > "$scratch/METADATA"
"$protoc" "--proto_path=$source_dir" --encode=litert.lm.proto.ExecutorMetadata \
    runtime/proto/executor_metadata.proto < "$recipe/model-metadata/$model-executor.textproto" \
    > "$scratch/EXECUTOR_METADATA"
cp "$input" "$scratch/model.task"
TZ=UTC touch -t 198001010000 "$scratch/METADATA" "$scratch/EXECUTOR_METADATA"
(cd "$scratch" && TZ=UTC zip -X -0 model.task METADATA EXECUTOR_METADATA >/dev/null)
while read -r name member hash; do
    [ "$name" = "$model" ] || continue
    [ "$member" != METADATA ] || continue
    unzip -p "$scratch/model.task" "$member" > "$scratch/member"
    [ "$(checksum "$scratch/member")" = "$hash" ] || {
        echo "Model member changed: $member" >&2; exit 1;
    }
done < "$recipe/model-metadata/members.tsv"
unzip -p "$scratch/model.task" METADATA > "$scratch/check-metadata"
cmp "$scratch/METADATA" "$scratch/check-metadata"
unzip -p "$scratch/model.task" EXECUTOR_METADATA > "$scratch/check-executor"
cmp "$scratch/EXECUTOR_METADATA" "$scratch/check-executor"
mv "$scratch/model.task" "$output"
printf 'Prepared %s; weights and tokenizer unchanged; SHA256=%s\n' "$model" "$(checksum "$output")"
