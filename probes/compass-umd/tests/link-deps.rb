#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted causal relink of actual full upstream UMD objects.
require 'open3'
require 'shellwords'
require 'fileutils'
abort 'usage: link-deps.rb COMPLETED_BUILD NEW_WORK' unless ARGV.length == 2
build = File.realpath(ARGV[0])
work = File.expand_path(ARGV[1])
abort 'work must be new' if File.exist?(work)
FileUtils.mkdir(work)
line = File.readlines("#{build}/logs/build.log").find { |l| l.start_with?("#{build}/cxx ") && l.include?(' -shared ') }
abort 'full shared link command absent' unless line
command = Shellwords.split(line)
abort 'require all 27 production objects' unless command.count { |p| p.end_with?('.o') } == 27
{'linux-ldl'=>'-ldl', 'missing-execinfo'=>nil}.each do |name, replacement|
  args = command.dup
  index = args.index('-lexecinfo') or abort 'no execinfo link input'
  replacement ? args[index] = replacement : args.delete_at(index)
  args[args.index('-o') + 1] = "#{work}/#{name}.so"
  out, err, status = Open3.capture3(*args)
  File.write("#{work}/#{name}.log", out + err)
  expected = name == 'linux-ldl' ? 'cannot find -ldl' : 'undefined reference to `backtrace'
  abort "wrong link failure: #{name}" unless !status.success? && err.include?(expected)
end
puts 'PASS: actual 27-object relinks reject libdl and missing libexecinfo under -z defs'
