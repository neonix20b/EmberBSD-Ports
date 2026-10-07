#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted negative contracts for the new preparation/extractor.
set -eu
[ "$#" -eq 3 ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive=$1
inputs=$2
work=$3
case "$work" in /*) ;; *) exit 2;;esac
[ ! -e "$work" ] || exit 2
mkdir -p "$work"
n=0
reject() {
 name=$1;shift
 if "$@" > "$work/$name.log" 2>&1;then echo "Guard accepted: $name" >&2;exit 1;fi
 n=$((n+1));printf 'REJECT: %s\n' "$name"
}
reject relative-work sh "$recipe/prepare-lifecycle.sh" "$archive" "$inputs" relative-lifecycle
reject existing-work sh "$recipe/prepare-lifecycle.sh" "$archive" "$inputs" "$work"
reject missing-archive sh "$recipe/prepare-lifecycle.sh" "$work/absent" "$inputs" "$work/missing"
cp -R "$recipe" "$work/recipe"
printf '\ncorrupt\n' >> "$work/recipe/patches/lifecycle-qemu-local.patch"
reject delta-hash sh "$work/recipe/prepare-lifecycle.sh" "$archive" "$inputs" "$work/delta-hash"
cp "$recipe/patches/lifecycle-qemu-local.patch" "$work/recipe/patches/lifecycle-qemu-local.patch"
printf '\ncorrupt\n' >> "$work/recipe/lifecycle-sources.tsv"
reject manifest-hash sh "$work/recipe/prepare-lifecycle.sh" "$archive" "$inputs" "$work/manifest-hash"
cp "$recipe/lifecycle-sources.tsv" "$work/recipe/lifecycle-sources.tsv"
mkdir "$work/inputs"
while IFS="$(printf '\t')" read -r file rev url sum;do case "$file" in ''|'#'*)continue;;esac;cp "$inputs/$file" "$work/inputs/$file";done < "$recipe/create-sources.tsv"
printf '\ncorrupt\n' >> "$work/inputs/utm-qemu-6601422-virtio-gpu-base.c"
reject base-input-hash sh "$recipe/prepare-lifecycle.sh" "$archive" "$work/inputs" "$work/base-input"
# Deliberately repin only the engineered mutation: strict application must still
# reject an offset even though the hunk content would otherwise apply.
ruby - "$work/recipe" <<'RUBY'
require 'digest'
p=ARGV[0];file=p+'/patches/lifecycle-qemu-local.patch';s=File.read(file);raise unless s.sub!('@@ -14,6 +14,8 @@','@@ -15,6 +15,8 @@');File.write(file,s)
f=p+'/lifecycle-sources.tsv';s=File.read(f);s.sub!(/(patch\tpatches\/lifecycle-qemu-local.patch\t)[a-f0-9]{64}/,"\\1"+Digest::SHA256.file(file).hexdigest);File.write(f,s)
f=p+'/prepare-lifecycle.sh';s=File.read(f);s.sub!(/= [a-f0-9]{64} \] \|\| \{ echo 'Lifecycle manifest mismatch'/,"= #{Digest::SHA256.file(p+'/lifecycle-sources.tsv').hexdigest} ] || { echo 'Lifecycle manifest mismatch'");File.write(f,s)
RUBY
reject offset-application sh "$work/recipe/prepare-lifecycle.sh" "$archive" "$inputs" "$work/offset"
grep -Eq 'offset|Non-exact lifecycle' "$work/offset-application.log"
cat > "$work/function.c" <<'C'
static void selected(void);
static void selected(void)
{
    return;
}
C
awk -v name=selected -f "$recipe/tests/extract-lifecycle.awk" "$work/function.c" > "$work/extracted.c"
[ "$(wc -l < "$work/extracted.c" | tr -d ' ')" -eq 4 ]
reject absent-body awk -v name=absent -f "$recipe/tests/extract-lifecycle.awk" "$work/function.c"
cat "$work/function.c" "$work/function.c" > "$work/duplicate.c"
reject duplicate-body awk -v name=selected -f "$recipe/tests/extract-lifecycle.awk" "$work/duplicate.c"
sed '$d' "$work/function.c" > "$work/truncated.c"
reject truncated-body awk -v name=selected -f "$recipe/tests/extract-lifecycle.awk" "$work/truncated.c"
reject missing-shape awk -v kind=struct -v name=VirtIOGPUGL -f "$recipe/tests/extract-backing-shape.awk" "$work/function.c"
# Seam rewrite input is pinned separately from the accepted source stage.
cp "$recipe/tests/backing.c" "$work/bad-backing.c"
printf '\n/* drift */\n' >> "$work/bad-backing.c"
reject backing-seam-drift ruby "$recipe/tests/lifecycle-seams.rb" backing "$work/bad-backing.c"
printf 'PASS: %s lifecycle negative guards\n' "$n"
