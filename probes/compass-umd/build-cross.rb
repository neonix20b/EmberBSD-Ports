#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted full upstream UMD source-probe recipe.
require 'digest'
require 'fileutils'
require 'open3'
require 'shellwords'
require 'json'

abort 'usage: build-cross.rb ORIGINAL_ARCHIVE NEW_WORK CROSS_TOOLS SYSROOT GNU_MAKE' unless ARGV.length == 5
archive, work_arg, tools_arg, sysroot_arg, make_arg = ARGV
archive, tools, sysroot, make = [archive, tools_arg, sysroot_arg, make_arg].map { |p| File.realpath(p) }
work = File.expand_path(work_arg)
abort 'NEW_WORK must be new and absolute, without whitespace' unless work_arg.start_with?('/') && !File.exist?(work) && work !~ /\s/
owner = File.dirname(File.realpath(__FILE__))
abort 'paths with whitespace are unsupported by upstream Makefile' if [archive, tools, sysroot, owner, make].any? { |p| p.match?(/\s/) }
row = File.readlines("#{owner}/sources.tsv").find { |l| l.start_with?("Compass_NPU_Driver\t") }.split
abort 'original archive SHA256 mismatch' unless Digest::SHA256.file(archive).hexdigest == row[3]
cc, cxx, ar, readelf = %w[gcc g++ ar readelf].map { |p| File.realpath("#{tools}/bin/aarch64--netbsd-#{p}") }
def space!(path)
  out, status = Open3.capture2('df', '-k', path)
  abort 'cannot read free space' unless status.success?
  abort 'stop: less than 2 GiB free' if out.lines.last.split[3].to_i < 2 * 1024 * 1024
end
space!(File.dirname(work))
FileUtils.mkdir(work)
%w[logs original source obj bundle bundle/bin bundle/lib bundle/source].each { |p| FileUtils.mkdir_p("#{work}/#{p}") }
def run(log, *cmd, dir: nil, env: {})
  File.write(log + '.command', Shellwords.join(cmd) + "\n")
  options = {out: log, err: [:child, :out]}
  options[:chdir] = dir if dir
  abort "failed: #{log}" unless system(env, *cmd, **options)
  File.read(log)
end
logs = "#{work}/logs"
abort 'compiler must target aarch64--netbsd' unless run("#{logs}/target.log", cxx, '-dumpmachine').strip == 'aarch64--netbsd'
abort 'require common GCC 16.2' unless run("#{logs}/compiler.log", cxx, '-dumpfullversion').strip == '16.2.0'
abort 'GNU make required' unless run("#{logs}/make.log", make, '--version').start_with?('GNU Make ')
input_paths = [archive, cc, cxx, ar, readelf, make] + Dir.glob("#{owner}/**/*").select { |p| File.file?(p) }
%w[cc1plus as ld].each do |name|
  path = run("#{logs}/#{name}.log", cxx, "-print-prog-name=#{name}").strip
  abort "unresolved compiler tool #{name}" unless path.start_with?('/') && File.executable?(path)
  input_paths << File.realpath(path)
end
inputs = input_paths.uniq.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] }
%w[original source].each do |tree|
  run("#{logs}/extract-#{tree}.log", 'tar', '-xzf', archive, '--strip-components=1', '-C', "#{work}/#{tree}")
end
source = "#{work}/source"
%w[0001-descriptor-lifetime.patch 0002-core-count-bounds.patch 0003-netbsd-source-probe.patch].each do |p|
  result = run("#{logs}/#{p}.log", 'patch', '-f', '-N', '-F0', '-p1', '-i', "#{owner}/patches/#{p}", dir: source)
  abort "patch used offsets/fuzz: #{p}" if result.match?(/offset|fuzz|FAILED|Reversed/i)
end
gcc_root = "#{sysroot}/usr/pkg/gcc16"
common_flags = ["--sysroot=#{sysroot}", "-B#{gcc_root}/lib/gcc/aarch64--netbsd/16.2.0/",
  '-nostdinc++', '-isystem', "#{gcc_root}/include/c++", '-isystem', "#{gcc_root}/include/c++/aarch64--netbsd",
  '-isystem', "#{gcc_root}/include/c++/backward", "-L#{gcc_root}/lib", '-Wl,-rpath,/usr/pkg/gcc16/lib', '-Wl,-t']
wrapper = "#{work}/cxx"
File.write(wrapper, "#!/bin/sh\nset -eu\nunset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH COMPILER_PATH GCC_EXEC_PREFIX\nexec #{Shellwords.join([cxx, *common_flags])} \"$@\"\n")
File.chmod(0755, wrapper)
run("#{logs}/uapi.log", RbConfig.ruby, "#{owner}/tests/uapi-cross.rb", "#{work}/original", source, wrapper, "#{work}/uapi")
umd = "#{source}/Linux/driver/umd"
arguments = ['BUILD_TARGET_OS=NetBSD', 'BUILD_TARGET_PLATFORM=hw', 'BUILD_UMD_API_TYPE=standard_api',
  'BUILD_AIPU_VERSION=aipu_all', 'BUILD_DEBUG_FLAG=release', 'BUILD_ANDROID_NDK=',
  'COMPASS_DRV_BTENVAR_UMD_V_MAJOR=6', 'COMPASS_DRV_BTENVAR_UMD_V_MINOR=1.1',
  'COMPASS_DRV_BTENVAR_UMD_SO_NAME=libaipudrv.so.6', 'COMPASS_DRV_BTENVAR_UMD_SO_NAME_FULL=libaipudrv.so.6.1.1',
  'COMPASS_DRV_BTENVAR_UMD_A_NAME_FULL=libaipudrv.a',
  "COMPASS_DRV_BTENVAR_UMD_BUILD_DIR=#{work}/obj", "BUILD_AIPU_DRV_ODIR=#{work}/bundle/lib", "CXX=#{wrapper}", "AR=#{ar}"]
environment = %w[CFLAGS CXXFLAGS CPPFLAGS LDFLAGS CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH LIBRARY_PATH COMPILER_PATH GCC_EXEC_PREFIX MAKEFLAGS MFLAGS].to_h { |k| [k, nil] }
space!(work)
run("#{logs}/build.log", make, '-j2', *arguments, 'standard_api', dir: umd, env: environment)
space!(work)
objects = Dir.glob("#{work}/obj/**/*.o").sort
abort "expected all 27 upstream translation units, got #{objects.length}" unless objects.length == 27
abort 'v3.2 objects missing' unless %w[job_v3_2 gm_v3_2].all? { |p| objects.any? { |f| File.basename(f) == "#{p}.o" } }
binary = "#{work}/bundle/bin/compass-no-device"
run("#{logs}/consumer-compile.log", wrapper, '-std=c++14', '-Wall', '-Wextra', '-Werror', '-O2', '-fPIE', '-pthread',
  '-MD', '-MF', "#{logs}/consumer.d", "-I#{umd}/include", '-c', "#{owner}/tests/no-device.cpp", '-o', "#{work}/consumer.o")
run("#{logs}/consumer.log", wrapper, '-pie', '-pthread', "#{work}/consumer.o", '-Wl,-z,defs', '-o', binary)
dso = "#{work}/bundle/lib/libaipudrv.so.6.1.1"
[dso, binary].each do |f|
  elf = run("#{logs}/#{File.basename(f)}.elf", readelf, '-h', '-d', f)
  abort "not AArch64 ELF: #{f}" unless elf.include?('AArch64') && elf.include?('ELF64') && elf.include?("little endian")
  paths = elf.scan(/\((?:RPATH|RUNPATH)\).*\[([^\]]+)\]/).flatten.flat_map { |p| p.split(':') }
  abort 'noncanonical runtime path' unless paths == ['/usr/pkg/gcc16/lib']
  abort 'libdl dependency forbidden on NetBSD' if elf.include?('[libdl.')
end
dso_elf = File.read("#{logs}/libaipudrv.so.6.1.1.elf")
abort 'missing full runtime dependencies' unless %w[libexecinfo.so.0 libstdc++.so.7 libgcc_s.so.1].all? { |n| dso_elf.include?("[#{n}]") }
abort 'wrong SONAME' unless dso_elf.match?(/\(SONAME\).*\[libaipudrv\.so\.6\]/)
members = run("#{logs}/archive.log", ar, 't', "#{work}/bundle/lib/libaipudrv.a").lines.map(&:strip)
abort 'static archive members differ' unless members.sort == objects.map { |p| File.basename(p) }.sort
# Record actual package runtime inputs, not a second bundled compiler runtime.
runtime = %w[libstdc++.so.7 libgcc_s.so.1].map { |p| File.realpath("#{gcc_root}/lib/#{p}") }
File.write("#{work}/bundle/runtime.sha256", runtime.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p.delete_prefix(sysroot)}\n" }.join)
inputs.merge!(runtime.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] })
# Compiler-generated dependencies capture all target headers used by the full build.
compiler_root = File.realpath(File.join(File.dirname(cxx), '..'))
allowed = [source, sysroot, compiler_root, owner].map { |p| p + '/' }
(Dir.glob("#{work}/obj/**/*.d") + ["#{logs}/consumer.d"]).each do |path|
  dependencies = Shellwords.split(File.read(path).gsub("\\\n", ' ').lines.first.split(':', 2).last)
  dependencies.each do |dep|
    p = File.realpath(File.expand_path(dep, umd))
    abort "foreign compile dependency: #{p}" unless allowed.any? { |root| p.start_with?(root) }
    inputs[p] = Digest::SHA256.file(p).hexdigest
  end
end
# GNU ld -t reports the actual link inputs, including startup files and DSOs.
%w[build consumer].each do |name|
  File.readlines("#{logs}/#{name}.log", chomp: true).grep(%r{^/[^\s]+\.(?:o|so(?:\.[\d.]+)?|a)$}).each do |path|
    p = File.realpath(path)
    abort "foreign link dependency: #{p}" unless (allowed + [work + '/']).any? { |root| p.start_with?(root) }
    inputs[p] = Digest::SHA256.file(p).hexdigest
  end
end
abort 'system-header receipt missing' unless inputs.keys.any? { |p| p.start_with?(sysroot + '/usr/include/') }
abort 'linker receipt missing execinfo' unless inputs.keys.any? { |p| p.start_with?(sysroot + '/usr/lib/libexecinfo.so') }
inputs[wrapper] = Digest::SHA256.file(wrapper).hexdigest
File.write("#{work}/inputs.sha256", inputs.sort.map { |p,h| "#{h}  #{p}\n" }.join)
inputs.each { |p,h| abort "input drift: #{p}" unless Digest::SHA256.file(p).hexdigest == h }
FileUtils.cp("#{owner}/run-no-device.sh", "#{work}/bundle/")
%w[tests/no-device.cpp tests/uapi-layout.cpp patches/0003-netbsd-source-probe.patch sources.tsv].each { |p| FileUtils.cp("#{owner}/#{p}", "#{work}/bundle/source/") }
FileUtils.cp("#{work}/inputs.sha256", "#{work}/bundle/source/")
File.write("#{work}/bundle/source/policy.json", JSON.pretty_generate({
  revision: row[1], paired_version: '6.1.1', units: 27, api: 'hardware standard_api aipu_all',
  boundary: 'Source probe only. Linux/AArch64 wire ABI retained; no native kernel transport. Requires absent /dev/aipu.',
  runtime: '/usr/pkg/gcc16/lib', jobs: 2
}) + "\n")
files = Dir.glob("#{work}/bundle/**/*").select { |p| File.file?(p) }.sort
File.write("#{work}/bundle/artifacts.sha256", files.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p.delete_prefix(work+'/bundle/')}\n" }.join)
run("#{logs}/bundle-verify.log", 'sh', "#{owner}/run-no-device.sh", '--verify-sysroot', "#{work}/bundle", sysroot)
run("#{logs}/linux-dry.log", make, '-n', *arguments.reject { |a| a.start_with?('BUILD_TARGET_OS=') }, 'BUILD_TARGET_OS=Linux', '-B', 'standard_api', dir: umd, env: environment)
abort 'Linux default link semantics changed' unless File.read("#{logs}/linux-dry.log").include?('-lpthread -ldl') && !File.read("#{logs}/linux-dry.log").include?('-lexecinfo')
size = Dir.glob("#{work}/**/*").select { |p| File.file?(p) && !File.symlink?(p) }.sum { |p| File.size(p) }
abort 'work exceeded 150 MiB bound' if size > 150 * 1024 * 1024
space!(work)
puts "PASS: complete 27-unit UMD shared/static cross build; #{size} bytes in work; target execution pending"
puts "Target bundle: #{work}/bundle"
