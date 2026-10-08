#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), inspect the real Mesa ABI test commands.
require 'digest'
require 'json'
require 'open3'

abort 'usage: mesa-cross-nm.rb MESA_BUILD TARGET_NM SSP_REGRESSION_OBJECT NEW_WORK' unless ARGV.length == 4
build, nm, object = ARGV.first(3).map { |path| File.realpath(path) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
Dir.mkdir(work)
intro = "#{build}/meson-info/intro-tests.json"
tests = JSON.parse(File.read(intro))
names = %w[es1-ABI-check es2-ABI-check libGL-ABI-check gbm-symbols-check egl-symbols-check]
names.each do |name|
  command = tests.find { |test| test['name'] == name }&.fetch('cmd')
  abort "missing actual ABI test #{name}" unless command
  index = command.index('--nm')
  platform = command.index('--target-system')
  abort "#{name} does not select the explicit target nm/NetBSD format" unless index && platform && File.realpath(command[index + 1]) == nm && command[platform + 1] == 'netbsd'
end
puts 'PASS: all five actual Mesa ABI commands select the explicit cross nm and NetBSD format'
header = File.binread(object, 20)
abort 'SSP regression object is not AArch64 ELF64' unless header.start_with?("\x7fELF\x02\x01") && header[18, 2].unpack1('v') == 183
out, status = Open3.capture2e(nm, '--version')
File.write("#{work}/nm-version.log", out)
abort 'target nm is not the selected GNU cross tool' unless status.success? && out.include?('GNU nm')
out, status = Open3.capture2e(nm, '-gP', object)
File.write("#{work}/exports.log", out)
symbols = out.lines.map(&:split)
abort 'cross nm did not decode the real Mesa object symbols' unless status.success? && %w[vl_csc_get_primaries_matrix vl_csc_get_rgbyuv_matrix].all? { |name| symbols.any? { |fields| fields[0, 2] == [name, 'T'] } }
puts 'PASS: selected cross nm decodes both real Mesa functions from AArch64 ELF'
File.write("#{work}/inputs.sha256", [intro, nm, object].map { |path| "#{Digest::SHA256.file(path).hexdigest}  #{path}\n" }.join)
