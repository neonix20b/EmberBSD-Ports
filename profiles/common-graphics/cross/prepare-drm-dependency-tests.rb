#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), real upstream tests and existing wscons contracts.
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'shellwords'
abort 'usage: prepare-drm-dependency-tests.rb CROSS_TOOLS SYSROOT PKG_CONFIG DRM_BUNDLE SEATD_SOURCE INPUT_SOURCE DISPLAY_SOURCE LIFTOFF_SOURCE NEW_WORK' unless ARGV.length == 9
tools, sysroot, pc, accepted, seatd, input, display, liftoff = ARGV.first(8).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
abort 'installed payload verification failed' unless system('sh', "#{accepted}/run-mesa-package-tests.sh", '--verify-sysroot', accepted, sysroot)
owner = File.dirname(File.realpath(__FILE__))
root = File.expand_path('../../..', owner)
cc, readelf = %w[gcc readelf].map { |n| "#{tools}/bin/aarch64--netbsd-#{n}" }
bundle = "#{work}/bundle"
FileUtils.mkdir_p(["#{bundle}/bin", "#{bundle}/source", "#{bundle}/data"])
inputs = [__FILE__, "#{owner}/run-drm-dependency-tests.sh", cc, readelf, pc]
%w[run-mesa-package-tests.sh mesa-package-files.sha256 mesa-package-links.tsv runtime-libraries.sha256].each do |name|
  FileUtils.cp("#{accepted}/#{name}", bundle)
  inputs << "#{accepted}/#{name}"
end
FileUtils.cp("#{owner}/run-drm-dependency-tests.sh", bundle)
FileUtils.cp_r("#{accepted}/source", "#{bundle}/source/provider-receipt")
env = {'PKG_CONFIG_PATH'=>'', 'PKG_CONFIG_LIBDIR'=>"#{sysroot}/usr/pkg/lib/pkgconfig:#{sysroot}/usr/pkg/share/pkgconfig", 'PKG_CONFIG_SYSROOT_DIR'=>sysroot}
def run(log, env, *command)
  File.write(log + '.command', Shellwords.join(command) + "\n")
  out, status = Open3.capture2e(env, *command)
  File.write(log, out)
  abort "command failed: #{log}" unless status.success?
  out.strip
end
base = [cc, "--sysroot=#{sysroot}", '-O2', '-D_NETBSD_SOURCE', '-fPIC', '-pie']
link = ["-L#{sysroot}/usr/pkg/lib", "-Wl,-rpath-link,#{sysroot}/usr/pkg/lib", "-Wl,-rpath-link,#{sysroot}/usr/pkg/gcc16/lib", '-Wl,-rpath,/usr/pkg/lib', '-Wl,-rpath,/usr/pkg/gcc16/lib']
checks = []
contracts = "#{root}/probes/wayland-utm/tests"
%w[seatd-keyboard.c wscons-absolute.c].each { |n| FileUtils.cp("#{contracts}/#{n}", "#{bundle}/source"); inputs << "#{contracts}/#{n}" }
inputs += ["#{seatd}/common/terminal.c", "#{seatd}/common/log.c", "#{seatd}/include/terminal.h"]
run("#{bundle}/source/seatd-object.log", {}, *base, '-std=c11', '-Wall', '-Wextra', '-Werror', "-I#{seatd}/include", '-Dioctl=seatd_test_ioctl', '-c', "#{seatd}/common/terminal.c", '-o', "#{work}/terminal.o")
run("#{bundle}/source/seatd-contract.log", {}, *base, '-std=c11', '-Wall', '-Wextra', '-Werror', "-I#{seatd}/include", "#{bundle}/source/seatd-keyboard.c", "#{work}/terminal.o", "#{seatd}/common/log.c", *link, '-o', "#{bundle}/bin/seatd-keyboard")
checks << ['seatd-keyboard', 'elf', 'bin/seatd-keyboard', '-']
build = "#{input}/output"
objects = Dir.glob("#{build}/libinput.so.*.p/*.o").reject { |p| p.end_with?('/src_wscons.c.o') }.sort
abort 'missing actual libinput objects' if objects.empty?
inputs += objects + Dir.glob("#{input}/src/*.{c,h}") + ["#{build}/config.h", "#{build}/compile_commands.json", "#{build}/liblibinput-util.a", "#{build}/liblibinput-util-libinput.a"]
flags = Shellwords.split(run("#{bundle}/source/input-pkgconfig.log", env, pc, '--cflags', '--libs', 'libudev'))
run("#{bundle}/source/input-contract.log", {}, *base, '-std=gnu99', "-I#{build}", "-I#{input}/src", "-I#{input}/include", "-I#{input}", "-I#{sysroot}/usr/pkg/include", "-I#{sysroot}/usr/pkg/include/linux", "-I#{sysroot}/usr/pkg/include/libepoll-shim", "#{bundle}/source/wscons-absolute.c", *objects, "#{build}/liblibinput-util.a", "#{build}/liblibinput-util-libinput.a", *flags, *link, '-lepoll-shim', '-lm', '-lrt', '-o', "#{bundle}/bin/wscons-absolute")
checks << ['wscons-absolute', 'elf', 'bin/wscons-absolute', '-']
# Preserve and select upstream's actual test metadata, including duplicate EDID cases.
%w[seatd display liftoff].zip([seatd, display, liftoff]).each do |name, source|
  metadata = "#{source}/output/meson-info/intro-tests.json"
  inputs << metadata
  FileUtils.cp(metadata, "#{bundle}/source/#{name}-intro-tests.json")
end
seat_tests = JSON.parse(File.read("#{seatd}/output/meson-info/intro-tests.json"))
abort 'upstream seatd test selection changed' unless seat_tests.map { |t| t.fetch('name') }.sort == %w[connection linked_list poller]
seat_tests.each do |test|
  command = test.fetch('cmd')
  abort 'unexpected seatd invocation' unless command.length == 1 && test['protocol'] == 'exitcode'
  executable = File.realpath(command.first)
  abort 'seatd test escaped build' unless executable.start_with?("#{seatd}/output/")
  inputs << executable
  dest = "bin/seatd-#{File.basename(executable)}"
  FileUtils.cp(executable, "#{bundle}/#{dest}")
  checks << ["seatd-#{test.fetch('name')}", 'elf', dest, '-']
end
FileUtils.cp_r("#{display}/test/data", "#{bundle}/data/edid")
%w[edid-decode-check.sh edid-print-check.sh].each { |n| inputs << "#{display}/test/#{n}"; FileUtils.cp("#{display}/test/#{n}", "#{bundle}/bin") }
inputs << "#{sysroot}/usr/pkg/bin/di-edid-decode"
FileUtils.cp("#{sysroot}/usr/pkg/bin/di-edid-decode", "#{bundle}/bin")
inputs << "#{display}/test/di-edid-print.c"
flags = Shellwords.split(run("#{bundle}/source/display-pkgconfig.log", env, pc, '--cflags', '--libs', 'libdisplay-info'))
run("#{bundle}/source/display-print.log", {}, *base, '-std=c11', "#{display}/test/di-edid-print.c", *flags, *link, '-o', "#{bundle}/bin/di-edid-print")
tests = JSON.parse(File.read("#{display}/output/meson-info/intro-tests.json"))
abort 'upstream EDID test selection changed' unless tests.length == 68
tests.each_with_index do |test, index|
  command = test.fetch('cmd')
  abort 'unexpected upstream EDID metadata' unless test['workdir'].nil? && test['protocol'] == 'exitcode' && (test.fetch('env').keys - %w[DI_EDID_DECODE DI_EDID_PRINT LD_LIBRARY_PATH DYLD_LIBRARY_PATH]).empty?
  abort 'unexpected upstream EDID command' unless command.length == 2 && %w[edid-decode-check.sh edid-print-check.sh].include?(File.basename(command.first)) && File.realpath(command.last).start_with?("#{display}/test/data/")
  checks << [format('display-%02d-%s', index, test.fetch('name')), 'edid', "bin/#{File.basename(command.first)}", "data/edid/#{File.basename(command.last)}"]
end
# Upstream liftoff tests deliberately mock libdrm; link that real mock directly
# into test executables, with installed libliftoff and no loader overrides.
flags = Shellwords.split(run("#{bundle}/source/liftoff-pkgconfig.log", env, pc, '--cflags', '--libs', 'libliftoff', 'libdrm'))
inputs += Dir.glob("#{liftoff}/test/*.{c,h}") + ["#{liftoff}/test/meson.build"]
tests = JSON.parse(File.read("#{liftoff}/output/meson-info/intro-tests.json"))
abort 'missing upstream liftoff tests' if tests.empty?
tests.each do |test|
  command = test.fetch('cmd')
  executable = File.basename(command.first)
  abort 'unexpected liftoff command' unless command.length <= 2 && executable.match?(/\A(?:test-[a-z]+|check_ndebug)\z/)
  unless File.exist?("#{bundle}/bin/liftoff-#{executable}")
    sources = ["#{liftoff}/test/#{executable.tr('-', '_')}.c"]
    sources << "#{liftoff}/test/libdrm_mock.c" unless executable == 'check_ndebug'
    run("#{bundle}/source/liftoff-#{executable}.log", {}, *base, '-std=c11', "-I#{liftoff}/include", "-I#{liftoff}/test", *sources, *flags, *link, '-Wl,--export-dynamic', '-o', "#{bundle}/bin/liftoff-#{executable}")
  end
  checks << ["liftoff-#{test.fetch('name')}", 'elf', "bin/liftoff-#{executable}", command.fetch(1, '-')]
end
Dir.glob("#{bundle}/bin/*").each do |path|
  next unless File.binread(path,4) == "\x7fELF"
  header = File.binread(path,20)
  abort 'expected AArch64 ELF' unless header.byteslice(0,6)=="\x7fELF\x02\x01" && header.byteslice(18,2).unpack1('v')==183
  text = run("#{bundle}/source/#{File.basename(path)}.elf.log", {}, readelf, '-d', path)
  # Meson build RPATHs may be present in copied upstream executables. Rebuild
  # rather than accepting a private target path or changing target loader search.
  paths = text.scan(/\((?:RPATH|RUNPATH)\).*\[([^\]]+)\]/).flatten.flat_map { |p| p.split(':') }.reject(&:empty?)
  abort "noncanonical RPATH: #{path}: #{paths}" unless (paths - %w[/usr/pkg/lib /usr/pkg/gcc16/lib]).empty?
end
File.write("#{bundle}/checks.tsv", checks.map { |c| c.join("\t")+"\n" }.join)
inputs += Dir.glob("#{display}/test/data/*")
File.write("#{bundle}/source/inputs.sha256", inputs.uniq.sort.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
File.write("#{bundle}/artifacts.sha256", Dir.glob("#{bundle}/**/*").select { |p| File.file?(p) }.sort.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p.delete_prefix(bundle+'/')}\n" }.join)
archive = "#{work}/drm-dependency-tests.tar.gz"
abort 'tar failed' unless system({'COPYFILE_DISABLE'=>'1'},'tar','--no-xattrs','-czf',archive,'-C',bundle,'.')
puts "#{checks.length} selected invocations; #{Digest::SHA256.file(archive).hexdigest}  #{archive}"
