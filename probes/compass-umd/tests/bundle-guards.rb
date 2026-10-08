#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted real runner integrity negatives; never executes target code.
require 'fileutils'
require 'open3'
abort 'usage: bundle-guards.rb BUNDLE SYSROOT NEW_WORK' unless ARGV.length == 3
bundle, sysroot = ARGV.first(2).map { |p| File.realpath(p) }
work = File.expand_path(ARGV[2])
abort 'work must be new' if File.exist?(work)
FileUtils.mkdir(work)
runner = File.expand_path('../run-no-device.sh', __dir__)
cases = %w[valid changed-consumer changed-dso missing-source extra-dso symlink-dso runtime-drift]
cases.each do |name|
  copy = "#{work}/#{name}"
  FileUtils.cp_r(bundle, copy)
  root = sysroot
  case name
  when 'changed-consumer' then File.open("#{copy}/bin/compass-no-device", 'ab') { |f| f.write('changed') }
  when 'changed-dso' then File.open("#{copy}/lib/libaipudrv.so.6.1.1", 'ab') { |f| f.write('changed') }
  when 'missing-source' then File.unlink("#{copy}/source/no-device.cpp")
  when 'extra-dso' then File.write("#{copy}/lib/foreign.so", 'foreign')
  when 'symlink-dso'
    File.unlink("#{copy}/lib/libaipudrv.so.6.1.1")
    File.symlink("#{bundle}/lib/libaipudrv.so.6.1.1", "#{copy}/lib/libaipudrv.so.6.1.1")
  when 'runtime-drift'
    root = "#{work}/runtime"
    File.readlines("#{copy}/runtime.sha256").each do |line|
      path = line.split.last
      FileUtils.mkdir_p(File.dirname(root + path))
      File.write(root + path, 'changed')
    end
  end
  out, err, status = Open3.capture3('sh', runner, '--verify-sysroot', copy, root)
  File.write("#{work}/#{name}.log", out + err)
  abort "wrong guard result: #{name}" unless status.success? == (name == 'valid')
end
puts 'PASS: intact bundle and 6 real integrity rejections before target execution'
