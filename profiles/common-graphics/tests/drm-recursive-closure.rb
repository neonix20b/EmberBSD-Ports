#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), execute the production recursive ELF guard.
require 'digest'
require 'fileutils'
require 'open3'
abort 'usage: drm-recursive-closure.rb BUNDLE SYSROOT CROSS_READELF NEW_WORK' unless ARGV.length == 4
bundle, sysroot, readelf = ARGV.first(3).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
source = File.expand_path('../cross/prepare-wlroots-drm.rb', __dir__)
text = File.read(source)
guard = text[/^# Check every recorded ELF.*?(?=^abort 'wrong target compiler')/m]
abort 'production recursive guard missing' unless guard&.include?('unrecorded recursive dependencies:')
# The generated probe executes the actual guard against actual target ELF files.
# Only its input manifest is varied; no pkg-config, readelf or target result is mocked.
File.write("#{work}/probe.rb", <<~'RB' + guard)
  require 'open3'
  require 'fileutils'
  bundle, sysroot, readelf, manifest, rejected = ARGV
  FileUtils.mkdir_p(bundle + '/source')
  runtime = File.readlines(manifest).to_h { |line| hash,path=line.chomp.split(/  /,2); [path,hash] }
  runtime.reject! { |path,_| File.basename(path).start_with?(rejected) } unless rejected == '-'
  def run(log, env, *command)
    out,status = Open3.capture2e(env,*command)
    File.write(log,out)
    abort 'real readelf failed' unless status.success?
    out
  end
RB
{
  'complete' => ['-', nil],
  'missing-udev' => ['libudev.so', 'requires libudev.so.0'],
  'missing-xcb-xkb' => ['libxcb-xkb.so', 'requires libxcb-xkb.so.1'],
  'missing-llvm' => ['libLLVM.so', 'requires libLLVM.so.23.1']
}.each do |name, (removed, diagnostic)|
  out,status = Open3.capture2e('ruby', "#{work}/probe.rb", "#{work}/#{name}", sysroot, readelf, "#{bundle}/runtime-libraries.sha256", removed)
  File.write("#{work}/#{name}.log", out)
  abort "unexpected #{name} result" unless diagnostic ? !status.success? && out.include?(diagnostic) : status.success?
  puts "PASS: actual recursive ELF closure #{name}"
end
paths = [__FILE__, source, readelf, "#{bundle}/runtime-libraries.sha256"]
File.write("#{work}/inputs.sha256", paths.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
puts 'PASS: host metadata checks only; no target runtime was executed'
