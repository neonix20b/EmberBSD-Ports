#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), installed libsfdo and session D-Bus acceptance.
require 'digest'
require 'fileutils'
require 'open3'
require 'shellwords'
abort 'usage: prepare-desktop-support.rb CROSS_TOOLS SYSROOT HOST_PKG_CONFIG TEXT_BUNDLE LIBSFDO_ARCHIVE NEW_WORK' unless ARGV.size == 6
tools, root, pc, base, archive = ARGV.first(5).map { |p| File.realpath(p) }
work = File.expand_path(ARGV[5])
abort 'NEW_WORK must be new and absolute' unless ARGV[5].start_with?('/') && !File.exist?(work) && !File.symlink?(work)
abort 'libsfdo archive mismatch' unless Digest::SHA256.file(archive).hexdigest == '9d74a9bff1f872e38ab662d8e2b5f6ecd404d7f82f84e9c324013f856688fa2d'
owner = File.dirname(File.realpath(__FILE__))
cc, elf = %w[gcc readelf].map { |n| tools + '/bin/aarch64--netbsd-' + n }
helpers = %w[run-desktop-support.sh desktop-session-bus.sh]
inputs = [__FILE__, archive, cc, elf, pc, base+'/artifacts.sha256', *helpers.map { |n| owner+'/'+n }]
hashes = inputs.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] }
abort 'base verification failed' unless system('sh', base+'/run-mesa-package-tests.sh', '--verify-sysroot', base, root)
%w[libsfdo-0.1.4nb1 dbus-1.16.2nb4].each do |name|
  metadata = base+'/source/'+name+'.CONTENTS'
  abort "missing installed package: #{name}" unless File.file?(metadata) && File.read(metadata).include?("@name #{name}\n")
end
FileUtils.mkdir_p(work)
bundle = work+'/bundle'
FileUtils.cp_r(base, bundle)
FileUtils.rm(bundle+'/artifacts.sha256')
helpers.each { |n| FileUtils.cp(owner+'/'+n, bundle+'/'+n) }
source = bundle+'/source/libsfdo'
FileUtils.mkdir_p(source)
abort 'source extraction failed' unless system('tar', '-xzf', archive, '--strip-components=1', '-C', source)
# Keep the full unchanged upstream license, tests, headers and fixture provenance.
File.write(bundle+'/source/desktop-provenance.txt', "libsfdo 0.1.4: unchanged upstream tests and fixtures\nhttps://gitlab.freedesktop.org/vyivel/libsfdo/-/archive/v0.1.4/libsfdo-v0.1.4.tar.gz\nSHA256: #{Digest::SHA256.file(archive).hexdigest}\n")
def run(log, env, *args)
  File.write(log+'.command', Shellwords.join(args)+"\n")
  out, err, status = Open3.capture3(env, *args)
  File.write(log, out+err)
  abort "command failed: #{log}" unless status.success?
  out.strip
end
abort 'wrong compiler target' unless run(work+'/compiler.log', {}, cc, '-dumpmachine') == 'aarch64--netbsd'
prefix = root+'/usr/pkg'
env = {'PKG_CONFIG_PATH'=>'', 'PKG_CONFIG_LIBDIR'=>prefix+'/lib/pkgconfig:'+prefix+'/share/pkgconfig', 'PKG_CONFIG_SYSROOT_DIR'=>root}
%w[basedir desktop-file desktop icon].each do |name|
  mod = 'libsfdo-'+name
  abort 'wrong libsfdo version' unless run(work+'/'+name+'.version', env, pc, '--modversion', mod) == '0.1.4'
  flags = Shellwords.split(run(work+'/'+name+'.pc', env, pc, '--cflags', '--libs', mod))
  binary = bundle+'/bin/sfdo-'+name
  run(bundle+'/source/sfdo-'+name+'.compile', {}, cc, "--sysroot=#{root}", '-D_NETBSD_SOURCE', '-std=gnu11', '-O2', '-fPIC', '-pie', '-I'+source+'/include',
      source+'/tests/'+name+'.c', *flags, '-Wl,-rpath-link,'+prefix+'/lib', '-Wl,-rpath,/usr/pkg/lib', '-o', binary)
  header = File.binread(binary,20)
  abort 'wrong ELF architecture' unless header.byteslice(0,6) == "\x7fELF\x02\x01" && header.byteslice(18,2).unpack1('v') == 183
  dynamic = run(bundle+'/source/sfdo-'+name+'.elf', {}, elf, '-d', binary)
  abort 'wrong runtime path' unless dynamic.scan(/\((?:RPATH|RUNPATH)\).*\[([^\]]+)\]/).flatten == ['/usr/pkg/lib']
  abort 'missing installed library dependency' unless dynamic.include?("[#{mod}.so.0]")
end
File.write(bundle+'/source/desktop-inputs.sha256', hashes.map { |p,h| "#{h}  #{p}\n" }.join)
hashes.each { |p,h| abort "input changed: #{p}" unless Digest::SHA256.file(p).hexdigest == h }
files = Dir.glob(bundle+'/**/*', File::FNM_DOTMATCH).select { |p| File.file?(p) }.sort
File.write(bundle+'/artifacts.sha256', files.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p.delete_prefix(bundle+'/')}\n" }.join)
abort 'final verification failed' unless system('sh', bundle+'/run-mesa-package-tests.sh', '--verify-sysroot', bundle, root)
tar = work+'/desktop-support.tar.gz'
abort 'archive failed' unless system({'COPYFILE_DISABLE'=>'1'}, 'tar', '--no-xattrs', '-czf', tar, '-C', bundle, '.')
puts "#{Digest::SHA256.file(tar).hexdigest}  #{tar}"
