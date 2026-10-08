#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), actual upstream epoll and timestamp consumers.
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'shellwords'

abort 'usage: input-cross.rb PREPARED_PKGSRC CROSS_MAKECONF SOURCE CROSS_CC SYSROOT MESON NEW_WORK' unless ARGV.length == 7
tree, conf, source, cc, sysroot, meson = ARGV.first(6).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
make = ENV.fetch('BMAKE', 'bmake')
recipe = "#{tree}/devel/libopeninput/Makefile"
base = [make, '-C', File.dirname(recipe), "MAKECONF=#{conf}"]
run = lambda do |name, command, success, **options|
  out, status = Open3.capture2e(*command, **options)
  File.write("#{work}/#{name}.log", out)
  File.write("#{work}/#{name}.command", Shellwords.join(command) + "\n")
  abort "unexpected status #{status.exitstatus}: #{name}" unless status.success? == success
  out
end
query = lambda do |name, *args|
  out = run.call(name, [*base, *args, 'show-vars', 'VARNAMES=MESON_ARGS BUILDLINK_DIR'], true)
  abort 'unexpected make output' unless out.lines.length == 2
  out.lines.map(&:chomp)
end
args, buildlink = query.call('cross-selection')
native, native_buildlink = query.call('native-selection', 'USE_CROSS_COMPILE=no')
abort 'cross epoll root is not the real dependency view' unless Shellwords.split(args).include?("-Depoll-dir=#{buildlink}")
abort 'native dependency search was not preserved' unless Shellwords.split(native).include?("-Depoll-dir=#{native_buildlink}")
puts 'PASS: actual native and cross recipes select their pkgsrc dependency view'

upstream = File.read("#{source}/meson.build")
block = upstream.split('############ libepoll-shim (BSD) ############', 2).last&.split('############ libinput-util.a ############', 2)&.first
abort 'upstream epoll block changed' unless block&.include?("include_directories(dir_libepoll / 'include' / 'libepoll-shim')") && block.include?("name : 'libepoll-shim check'")
small = "#{work}/epoll-source"
FileUtils.mkdir_p(small)
File.write("#{small}/meson.build", "project('upstream-epoll-consumer', 'c')\ncc = meson.get_compiler('c')\nprefix = '#define _GNU_SOURCE 1'\ndep_rt = cc.find_library('rt')\n" + block)
File.write("#{small}/meson_options.txt", "option('epoll-dir', type : 'string', value : '')\n")
File.write("#{work}/cross.ini", <<~INI)
  [binaries]
  c = '#{cc}'
  [built-in options]
  c_args = ['--sysroot=#{sysroot}']
  c_link_args = ['--sysroot=#{sysroot}']
  [host_machine]
  system = 'netbsd'
  cpu_family = 'aarch64'
  cpu = 'aarch64'
  endian = 'little'
INI
setup = [meson, 'setup', '--cross-file', "#{work}/cross.ini", '--prefix=/usr/pkg', '--wrap-mode=nofallback']
red = run.call('epoll-original', [*setup, "#{work}/epoll-red", small], false)
abort 'original epoll search did not reproduce the missing target-prefix directory' unless red.include?('Include dir /usr/pkg/include/libepoll-shim does not exist')
green = run.call('epoll-adapted', [*setup, "-Depoll-dir=#{buildlink}", "#{work}/epoll-green", small], true)
abort 'real epoll link check did not pass' unless green.match?(/libepoll-shim check.*YES/)
puts 'PASS: actual upstream epoll block fails with the target prefix and links through buildlink'

commands = "#{source}/output/compile_commands.json"
entry = JSON.parse(File.read(commands)).find { |e| e['file'].end_with?('/wscons.c') }
abort 'missing actual wscons compile command' unless entry
flags = Shellwords.split(entry.fetch('command')).drop(1)
clean = []
until flags.empty?
  arg = flags.shift
  if %w[-o -MF -MQ -MT].include?(arg)
    flags.shift
  elsif !%w[-MD -MMD -c].include?(arg) && arg != entry.fetch('file')
    clean << arg
  end
end
current = File.read("#{source}/src/wscons.c")
start = current.index('wscons_udev_handler(void *data)')
finish = current.index('static int', start)
abort 'missing actual hotplug timestamp consumer' unless start && finish
handler = current[start...finish]
abort 'upstream typed timestamp API changed' unless handler.scan('usec_from_timespec(&ts)').length == 2 && handler.include?('usec_t time;')
legacy = handler.sub('usec_t time;', 'uint64_t time;').gsub('usec_from_timespec(&ts)', 's2us(ts.tv_sec) + ns2us(ts.tv_nsec)')
File.write("#{work}/legacy-time.c", current[0...start] + legacy + current[finish..])
File.write("#{work}/missing-ioctl.c", current.sub("#include <sys/ioctl.h>\n", ''))
syntax = [cc, "--sysroot=#{sysroot}", *clean, "-I#{source}/src", '-fsyntax-only', '-fdiagnostics-color=never']
red = run.call('time-api-red', [*syntax, "#{work}/legacy-time.c"], false, chdir: entry.fetch('directory'))
abort 'legacy hotplug control did not fail on the upstream timestamp API' unless red.include?('s2us') && red.include?('incompatible type for argument 2')
red = run.call('ioctl-header-red', [*syntax, "#{work}/missing-ioctl.c"], false, chdir: entry.fetch('directory'))
abort 'missing ioctl prototype control did not fail' unless red.match?(/implicit declaration of function .ioctl/)
run.call('timestamp-and-ioctl-green', [*syntax, "#{source}/src/wscons.c"], true, chdir: entry.fetch('directory'))
puts 'PASS: actual wscons TU rejects the old timestamp API and missing ioctl prototype; adapted TU compiles'
inputs = [__FILE__, recipe, conf, cc, meson, commands, "#{source}/src/wscons.c", "#{source}/src/util-time.h", "#{source}/meson.build"]
File.write("#{work}/inputs.sha256", inputs.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
puts 'PASS: configure and compile regressions only; wscons target behavior is a separate contract'
