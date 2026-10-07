#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted exact wait-stage negative contracts.
set -eu
[ "$#" -eq 3 ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive=$1 inputs=$2 work=$3
case "$work" in /*) ;; *) exit 2;;esac
[ ! -e "$work" ] || exit 2
mkdir -p "$work"
n=0
reject(){ name=$1;shift;if "$@" > "$work/$name.log" 2>&1;then echo "Guard accepted: $name" >&2;exit 1;fi;n=$((n+1));printf 'REJECT: %s\n' "$name"; }
reject relative-work sh "$recipe/prepare-wait.sh" "$archive" "$inputs" relative-wait
reject existing-work sh "$recipe/prepare-wait.sh" "$archive" "$inputs" "$work"
reject missing-archive sh "$recipe/prepare-wait.sh" "$work/absent" "$inputs" "$work/missing"
cp -R "$recipe" "$work/recipe"
printf '\ncorrupt\n' >> "$work/recipe/patches/wait-renderer-local.patch"
reject delta-hash sh "$work/recipe/prepare-wait.sh" "$archive" "$inputs" "$work/delta"
cp "$recipe/patches/wait-renderer-local.patch" "$work/recipe/patches/wait-renderer-local.patch"
printf '\ncorrupt\n' >> "$work/recipe/wait-sources.tsv"
reject manifest-hash sh "$work/recipe/prepare-wait.sh" "$archive" "$inputs" "$work/manifest"
for mutation in coordinate input output;do
 cp "$recipe/prepare-wait.sh" "$work/recipe/prepare-wait.sh"
 cp "$recipe/wait-sources.tsv" "$work/recipe/wait-sources.tsv"
 cp "$recipe/patches/wait-qemu-local.patch" "$work/recipe/patches/wait-qemu-local.patch"
 ruby - "$work/recipe" "$mutation" <<'RUBY'
require 'digest'
p,kind=ARGV;manifest=p+'/wait-sources.tsv';s=File.read(manifest)
if kind=='coordinate'
 file=p+'/patches/wait-qemu-local.patch';delta=File.read(file)
 raise unless delta.sub!(/@@ -(\d+),/){"@@ -#{$1.to_i+1},"}
 File.write(file,delta);s.sub!(/(patch\tpatches\/wait-qemu-local.patch\t)[a-f0-9]{64}/,"\\1"+Digest::SHA256.file(file).hexdigest)
else
 raise unless s.sub!(/(#{kind}\tqemu\/[^\t]+\t)[a-f0-9]{64}/,"\\1"+'0'*64)
end
File.write(manifest,s);file=p+'/prepare-wait.sh';s=File.read(file)
raise unless s.sub!(/= [a-f0-9]{64} \] \|\| \{ echo 'Wait manifest mismatch'/,"= #{Digest::SHA256.file(manifest).hexdigest} ] || { echo 'Wait manifest mismatch'")
File.write(file,s)
RUBY
 reject "$mutation-check" sh "$work/recipe/prepare-wait.sh" "$archive" "$inputs" "$work/$mutation"
 case "$mutation" in coordinate) grep -q 'Non-exact lifecycle hunk' "$work/$mutation-check.log";;input) grep -q 'Wait input mismatch' "$work/$mutation-check.log";;output) grep -q 'Wait output mismatch' "$work/$mutation-check.log";;esac
done
sh "$recipe/prepare-wait.sh" "$archive" "$inputs" "$work/extraction" > "$work/extraction-prepare.log"
file=$work/extraction/renderer-wait/src/vrend/vrend_renderer.c
cp "$file" "$work/complete.c"
for mutation in absent duplicate truncated;do
 cp "$work/complete.c" "$file"
 ruby - "$file" "$mutation" <<'RUBY'
p,mode=ARGV;s=File.read(p)
if mode=='absent'
 raise unless s.sub!('static int do_wait(', 'static int absent_wait(')
elsif mode=='duplicate'
 s+="\nstatic int do_wait(void)\n{\n return 0;\n}\n"
else
 start=s.index('static int do_wait(');raise unless start
 finish=s.index("\n}\n",start);raise unless finish
 s[finish+1]=''
end
File.write(p,s)
RUBY
 reject "$mutation-extraction" sh "$recipe/tests/extract-wait-renderer.sh" "$work/extraction" "$work/extract-$mutation" patched
 grep -q 'Unexpected lifecycle extraction shape' "$work/$mutation-extraction.log"
done
# New seam extension refuses drift of the accepted C8c3 API boundary.
cp "$work/complete.c" "$file"
sh "$recipe/tests/extract-wait-qemu.sh" "$work/extraction" "$work/valid-qemu" patched > "$work/valid-qemu.log"
cp "$recipe/tests/completion-api.h" "$work/valid-qemu/completion-api.h"
printf '\n/* drift */\n' >> "$work/valid-qemu/completion-api.h"
reject accepted-seam-drift ruby "$recipe/tests/wait-qemu-seams.rb" "$work/valid-qemu"
grep -q 'Accepted completion API seam drift' "$work/accepted-seam-drift.log"
printf 'PASS: %s wait negative guards\n' "$n"
