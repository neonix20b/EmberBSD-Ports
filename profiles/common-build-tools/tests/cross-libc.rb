#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted). Exercise the real cross-profile libc guard.
require 'fileutils'
require 'open3'
abort 'Usage: cross-libc.rb BMAKE NEW_WORK' unless ARGV.size == 2
bmake = File.realpath(ARGV[0])
work = File.expand_path(ARGV[1])
abort 'new absolute work required' unless ARGV[1].start_with?('/') && !File.exist?(work)
root = File.expand_path('../cross/mk.conf', __dir__)
sysroot = work + '/sysroot'
FileUtils.mkdir_p(sysroot + '/usr/lib')
FileUtils.mkdir_p(sysroot + '/lib')
File.write(work + '/Makefile', <<~MAKE)
  BSD_PKG_MK=yes
  PKGPATH=devel/ember-libc-fixture
  EMBERBSD_CROSS_TOOLS=#{work}
  EMBERBSD_CROSS_HOST_PREFIX=#{work}
  EMBERBSD_CROSS_SYSROOT=#{sysroot}
  RUN=@
  .include "#{root}"
MAKE
canonical = sysroot + '/lib/libc.so.12.224'
File.write(canonical, "accepted fork libc fixture\n")
aliases = %w[/lib/libc.so /lib/libc.so.12 /usr/lib/libc.so /usr/lib/libc.so.12]
aliases.each { |p| File.symlink(canonical, sysroot + p) }
check = lambda do |name, pass|
  output, status = Open3.capture2e(bmake, '-f', work + '/Makefile', 'pre-extract')
  File.write(work + '/' + name + '.log', output)
  abort "#{name}: unexpected guard result: #{output}" unless status.success? == pass
  abort "#{name}: failed for another reason" if !pass && !output.include?('Missing or divergent EmberBSD libc alias:')
end
check.call('consistent-aliases', true)
aliases.each_with_index do |p, index|
  File.unlink(sysroot + p)
  check.call("missing-#{index}", false)
  File.write(sysroot + p, "unrelated upstream libc fixture\n")
  check.call("divergent-#{index}", false)
  File.unlink(sysroot + p)
  File.symlink(canonical, sysroot + p)
end
check.call('restored-aliases', true)
puts 'PASS: cross profile accepts canonical aliases and rejects four missing and four divergent libc paths'
