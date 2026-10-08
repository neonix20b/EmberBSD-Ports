#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), released FriBidi make-rule regression.
require 'digest'
require 'fileutils'
require 'open3'

abort 'usage: fribidi-cross.rb BUILT_FRIBIDI_SOURCE NEW_WORK' unless ARGV.length == 2
source = File.realpath(ARGV[0])
work = File.expand_path(ARGV[1])
abort 'NEW_WORK must be new and absolute' unless ARGV[1].start_with?('/') && !File.exist?(work)
make = ENV.fetch('GMAKE', 'gmake')
original = File.read("#{source}/bin/Makefile")
expression = /ifneq \(\$\(build\),\$\(host\)\)\n# Release archives.*?\nelse\n(%.1: %\n.*?--output=\$@)\nendif/m
match = original.match(expression)
abort 'expected cross manpage rule missing' unless match
facts = %w[build host].map do |name|
  original.lines.find { |line| line.start_with?("#{name} = ") } or abort "missing #{name}"
end.join
elf = "#{source}/bin/.libs/fribidi"
abort 'fixture requires the actual cross-built ELF' unless File.binread(elf, 4) == "\x7fELF"
FileUtils.mkdir_p(work)
%w[original patched missing].each do |variant|
  dir = "#{work}/#{variant}"
  FileUtils.mkdir_p(dir)
  # Extract the exact generated rule and its target/build facts. Other targets
  # must not rebuild or modify the supplied completed source tree.
  File.write("#{dir}/Makefile", facts + (variant == 'original' ? match[1] : match[0]) + "\n")
  FileUtils.cp("#{source}/bin/fribidi", "#{dir}/fribidi")
  FileUtils.ln_s("#{source}/bin/.libs", "#{dir}/.libs")
  unless variant == 'missing'
    FileUtils.cp("#{source}/bin/fribidi.1", "#{dir}/fribidi.1")
    File.utime(Time.at(1), Time.at(1), "#{dir}/fribidi.1")
  end
end
run = lambda do |variant, *args|
  out, status = Open3.capture2e(make, '--no-print-directory', '-C', "#{work}/#{variant}",
    "srcdir=#{source}/bin", "top_srcdir=#{source}", "top_builddir=#{source}", *args, 'fribidi.1')
  File.write("#{work}/#{variant}#{args.empty? ? '' : '-native'}.log", out)
  [out, status]
end
out, status = run.call('original')
abort 'original target-execution failure not reproduced' if status.success? ||
  !out.include?('help2man') || !out.match?(/not executable: 64-bit ELF|Exec format error/)
puts 'RED: original released make rule tries to execute the target ELF for help2man'
out, status = run.call('patched')
abort "patched release page failed: #{out}" unless status.success?
abort 'release manpage changed' unless Digest::SHA256.file("#{work}/patched/fribidi.1").hexdigest ==
  Digest::SHA256.file("#{source}/bin/fribidi.1").hexdigest
puts 'GREEN: cross build retains the exact upstream release manpage'
out, status = run.call('missing')
abort 'missing release page was accepted' if status.success? || !out.include?('Missing release manpage')
puts 'GREEN: missing release page fails clearly'
before, status = run.call('original', '-n', 'build=native', 'host=native')
abort 'original native rule could not be inspected' unless status.success?
after, status = run.call('patched', '-n', 'build=native', 'host=native')
abort 'native rule changed' unless status.success? &&
  before.gsub("#{work}/original", 'FIXTURE') == after.gsub("#{work}/patched", 'FIXTURE')
puts 'GREEN: native help2man recipe remains unchanged'
paths = [__FILE__, "#{source}/bin/Makefile", elf, "#{source}/bin/fribidi.1"]
File.write("#{work}/inputs.sha256", paths.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
