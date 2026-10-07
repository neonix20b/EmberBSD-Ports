#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; collect Meson's actual target-test list without a new Python helper.
set -eu
[ "$#" -eq 3 ] || { echo 'Usage: stage-mesa-tests.sh MESA_BUILD MESA_SOURCE BUNDLE' >&2; exit 2; }
build=$1 source_dir=$2 bundle=$3
[ -d "$bundle" ] && [ ! -e "$bundle/tests" ] && [ ! -e "$bundle/fixtures" ]
mkdir "$bundle/tests" "$bundle/fixtures"
ruby -rjson -rfileutils - "$build" "$source_dir" "$bundle" <<'RUBY'
build,source,bundle=ARGV.map { |path| File.realpath(path) }
tests=JSON.parse(File.read("#{build}/meson-info/intro-tests.json"))
manifest=[]
tests.each do |test|
  command=test.fetch('cmd')
  next unless command.length==1 && command[0].start_with?("#{build}/")
  executable=command[0]
  next unless File.binread(executable,4)=="\x7fELF"
  name=test.fetch('name')
  basename=File.basename(executable)
  abort 'Unsafe test name' unless [name,basename].all? { |s| s.match?(/\A[A-Za-z0-9_-]+\z/) }
  FileUtils.cp(executable,"#{bundle}/tests/#{basename}")
  manifest << [name,basename].join("\t")
end
abort 'No target ELF tests found' if manifest.empty?
File.write("#{bundle}/upstream-tests.tsv",manifest.join("\n")+"\n")
FileUtils.cp_r("#{source}/src/util/tests/drirc_configdir","#{bundle}/fixtures")
RUBY
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
cp "$script_dir/run-mesa-upstream.sh" "$bundle/"
echo 'Staged actual target ELF tests; run-mesa-upstream.sh bounds each to 120 seconds.'
