#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), cross-built EGL/Wayland acceptance client.
require 'digest'
require 'fileutils'
require 'json'
abort 'usage: build-labwc-client.rb CROSS_TOOLS SYSROOT SCANNER SCREENCOPY_XML NEW_WORK' unless ARGV.size == 5
cross, sysroot, scanner, screencopy = ARGV.first(4).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'new absolute work required' unless ARGV.last.start_with?('/') && !File.exist?(work)
source = File.expand_path('../tests/labwc-session.c', __dir__)
xdg = sysroot + '/usr/pkg/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml'
# Selected protocols: wayland-protocols 1.49 and wlroots 0.20.2.
{xdg => '1ab24fef0d2e52eda62a44279fb9553dbe707dc2956bd4e5a59a9ac0990213b2',
 screencopy => '383c4bc33e0e293981caa8e82f83156012f10e00f5e39c8db90662a20c4e47e3'}.each do |path, expected|
  abort "protocol checksum mismatch: #{path}" unless Digest::SHA256.file(path).hexdigest == expected
end
FileUtils.mkdir_p(work)
[[xdg, 'xdg-shell'], [screencopy, 'wlr-screencopy']].each do |xml, name|
  abort 'scanner header failed' unless system(scanner, 'client-header', xml, work + '/' + name + '-client-protocol.h')
  abort 'scanner code failed' unless system(scanner, 'private-code', xml, work + '/' + name + '-protocol.c')
end
command = [cross + '/bin/aarch64--netbsd-gcc', '--sysroot=' + sysroot,
  '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
  '-I' + sysroot + '/usr/pkg/include', '-I' + work,
  '-L' + sysroot + '/usr/pkg/lib', '-Wl,-rpath,/usr/pkg/lib', '-Wl,-rpath,/usr/pkg/gcc16/lib',
  '-Wl,-rpath-link,' + sysroot + '/usr/pkg/lib', '-Wl,-rpath-link,' + sysroot + '/usr/pkg/gcc16/lib',
  source, work + '/xdg-shell-protocol.c', work + '/wlr-screencopy-protocol.c',
  '-lwayland-client', '-lwayland-egl', '-lEGL', '-lGLESv2', '-o', work + '/labwc-session']
File.write(work + '/command.json', JSON.pretty_generate(command) + "\n")
abort 'client compilation failed' unless system(*command, out: work + '/build.log', err: [:child, :out])
File.write(work + '/inputs.sha256', [__FILE__, source, scanner, xdg, screencopy, command.first].map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
File.write(work + '/binary.sha256', "#{Digest::SHA256.file(work + '/labwc-session').hexdigest}  labwc-session\n")
puts 'PASS: pinned protocols generated and labwc client cross-built; execution remains separate'
