#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted exact preparation and extraction negative guards.
set -eu
[ "$#" -eq 3 ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive=$1 inputs=$2 work=$3
case "$work" in /*) ;; *) exit 2;;esac
[ ! -e "$work" ] || exit 2
mkdir -p "$work"
n=0
reject() {
 name=$1;shift
 if "$@" > "$work/$name.log" 2>&1;then echo "Guard accepted: $name" >&2;exit 1;fi
 n=$((n+1));printf 'REJECT: %s\n' "$name"
}
reject relative-work sh "$recipe/prepare-completion.sh" "$archive" "$inputs" relative-completion
reject existing-work sh "$recipe/prepare-completion.sh" "$archive" "$inputs" "$work"
reject missing-archive sh "$recipe/prepare-completion.sh" "$work/absent" "$inputs" "$work/missing"
cp -R "$recipe" "$work/recipe"
printf '\ncorrupt\n' >> "$work/recipe/patches/completion-qemu-local.patch"
reject delta-hash sh "$work/recipe/prepare-completion.sh" "$archive" "$inputs" "$work/delta"
cp "$recipe/patches/completion-qemu-local.patch" "$work/recipe/patches/completion-qemu-local.patch"
printf '\ncorrupt\n' >> "$work/recipe/completion-sources.tsv"
reject manifest-hash sh "$work/recipe/prepare-completion.sh" "$archive" "$inputs" "$work/manifest"
cp "$recipe/completion-sources.tsv" "$work/recipe/completion-sources.tsv"
# Repin engineered mutations so they reach the independent exact-context,
# accepted-input and complete-output checks instead of only hash rejection.
for mutation in coordinate input output;do
 cp "$recipe/prepare-completion.sh" "$work/recipe/prepare-completion.sh"
 cp "$recipe/completion-sources.tsv" "$work/recipe/completion-sources.tsv"
 cp "$recipe/patches/completion-qemu-local.patch" "$work/recipe/patches/completion-qemu-local.patch"
 ruby - "$work/recipe" "$mutation" <<'RUBY'
require 'digest'
p,kind=ARGV;manifest=p+'/completion-sources.tsv';s=File.read(manifest)
if kind=='coordinate'
 file=p+'/patches/completion-qemu-local.patch';delta=File.read(file)
 raise unless delta.sub!('@@ -1084,6 +1084,23 @@','@@ -1085,6 +1084,23 @@')
 File.write(file,delta);s.sub!(/(patch\tpatches\/completion-qemu-local.patch\t)[a-f0-9]{64}/,"\\1"+Digest::SHA256.file(file).hexdigest)
else
 raise unless s.sub!(/(#{kind}\tqemu\/[^\t]+\t)[a-f0-9]{64}/,"\\1"+'0'*64)
end
File.write(manifest,s)
file=p+'/prepare-completion.sh';s=File.read(file)
raise unless s.sub!(/= [a-f0-9]{64} \] \|\| \{ echo 'Completion manifest mismatch'/,"= #{Digest::SHA256.file(manifest).hexdigest} ] || { echo 'Completion manifest mismatch'")
File.write(file,s)
RUBY
 reject "$mutation-check" sh "$work/recipe/prepare-completion.sh" "$archive" "$inputs" "$work/$mutation"
 case "$mutation" in coordinate) grep -q 'Non-exact lifecycle hunk' "$work/$mutation-check.log";;input) grep -q 'Completion input mismatch' "$work/$mutation-check.log";;output) grep -q 'Completion output mismatch' "$work/$mutation-check.log";;esac
done
sh "$recipe/prepare-completion.sh" "$archive" "$inputs" "$work/extraction" > "$work/extraction-prepare.log"
file=$work/extraction/qemu/completion/hw/display/virtio-gpu-virgl.c
cp "$file" "$work/complete.c"
for mutation in absent duplicate truncated;do
 cp "$work/complete.c" "$file"
 ruby - "$file" "$mutation" <<'RUBY'
p,mode=ARGV;s=File.read(p)
if mode=='absent'
 raise unless s.sub!('static void virgl_cmd_submit_3d(', 'static void absent_submit(')
elsif mode=='duplicate'
 s+="\nstatic void virgl_cmd_submit_3d(void)\n{\n}\n"
else
 start=s.index('static void virgl_cmd_submit_3d(');raise unless start
 finish=s.index("\n}\n",start);raise unless finish
 s[finish+1]='' # Remove only this closing brace; retain later functions.
end
File.write(p,s)
RUBY
 reject "$mutation-extraction" sh "$recipe/tests/extract-completion.sh" "$work/extraction" "$work/extract-$mutation" patched
 grep -q 'Unexpected lifecycle extraction shape' "$work/$mutation-extraction.log"
done
cp "$recipe/tests/lifecycle.c" "$work/drift.c"
printf '\n/* drift */\n' >> "$work/drift.c"
reject accepted-seam-drift ruby "$recipe/tests/completion-seams.rb" "$work/drift.c"
printf 'PASS: %s completion negative guards\n' "$n"
