#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), real bundle and installed-payload refusal tests.
require 'digest'
require 'fileutils'
require 'open3'

abort 'usage: epoxy-bundle.rb BUNDLE SYSROOT NEW_WORK' unless ARGV.length == 3
bundle, sysroot = ARGV.first(2).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
runner = "#{bundle}/run-epoxy-tests.sh"

def check(work, name, expected, *command)
  out, err, status = Open3.capture3(*command)
  File.write("#{work}/#{name}.log", out + err)
  abort "FAIL: #{name}" unless (expected.nil? ? status.success? : !status.success? && (out + err).include?(expected))
  puts "PASS: #{name}"
end
check(work, 'original', nil, 'sh', runner, '--verify-sysroot', bundle, sysroot)
changed = "#{work}/changed-bundle"
FileUtils.cp_r(bundle, changed)
File.open("#{changed}/bin/epoxy-render", 'ab') { |f| f.write('modified actual ELF') }
check(work, 'changed-elf', 'Bundle drift: bin/epoxy-render', 'sh', "#{changed}/run-epoxy-tests.sh", changed, "#{work}/must-not-run")
abort 'target execution started after artifact corruption' if File.exist?("#{work}/must-not-run")
FileUtils.rm_r(changed)
fixture = "#{work}/sysroot-fixture"
paths = %w[installed-files.sha256 runtime-libraries.sha256].flat_map { |n| File.readlines("#{bundle}/#{n}").map { |l| l.chomp.split(/  /,2)[1] } }.uniq
paths.each do |path|
  abort 'unsafe installed fixture path' unless path.start_with?('/usr/pkg/') && !path.split('/').include?('..')
  destination = fixture + path
  FileUtils.mkdir_p(File.dirname(destination))
  FileUtils.ln(File.realpath(sysroot + path), destination)
end
File.readlines("#{bundle}/installed-links.tsv").each do |line|
  path, target = line.chomp.split("\t",2)
  FileUtils.rm_f(fixture + path)
  FileUtils.ln_s(target, fixture + path)
end
check(work, 'original-file-fixture', nil, 'sh', runner, '--verify-sysroot', bundle, fixture)
%w[/usr/pkg/include/epoxy/gl.h /usr/pkg/lib/libepoxy.so.0.0.0].each_with_index do |path, i|
  original_hash = Digest::SHA256.file(sysroot + path).hexdigest
  # Replace the fixture's hard link atomically; never write through it.
  File.binwrite(fixture + path + '.changed', File.binread(fixture + path) + 'changed installed payload')
  File.rename(fixture + path + '.changed', fixture + path)
  check(work, "installed-drift-#{i}", 'Installed drift:', 'sh', runner, '--verify-sysroot', bundle, fixture)
  abort 'source sysroot was changed' unless Digest::SHA256.file(sysroot + path).hexdigest == original_hash
  FileUtils.rm(fixture + path)
  FileUtils.ln(sysroot + path, fixture + path)
end
FileUtils.rm_r(fixture)
puts 'PASS: five real-artifact integrity cases; no target code executed and source sysroot unchanged'
