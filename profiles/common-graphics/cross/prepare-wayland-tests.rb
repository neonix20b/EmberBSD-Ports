#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; preserve the actual upstream Meson test selection for a target run.
require 'json'
require 'fileutils'
require 'digest'

abort "Usage: #{$PROGRAM_NAME} WRKSRC TARGET_SYSROOT NEW_BUNDLE" unless ARGV.size == 3
source, sysroot = ARGV.take(2).map { |p| File.realpath(p) }
bundle = File.expand_path(ARGV[2])
abort 'Bundle already exists' if File.exist?(bundle)
build = File.join(source, 'output')
info = JSON.parse(File.read(File.join(build, 'meson-info/intro-projectinfo.json')))
abort 'Expected Wayland 1.26.0' unless info.values_at('descriptive_name', 'version') == ['wayland', '1.26.0']
tests = JSON.parse(File.read(File.join(build, 'meson-info/intro-tests.json')))
abort 'Expected all 26 enabled upstream tests' unless tests.size == 26
FileUtils.mkdir_p(File.join(bundle, 'tests'))
FileUtils.cp(File.join(source, 'COPYING'), bundle)
FileUtils.cp(File.join(build, 'meson-info/intro-tests.json'), bundle)
FileUtils.cp(File.join(build, 'meson-info/intro-projectinfo.json'), bundle)
FileUtils.cp_r(File.join(source, 'tests/data'), File.join(bundle, 'tests'))
FileUtils.cp(File.join(__dir__, 'run-wayland-tests.sh'), bundle)

names = []
File.open(File.join(bundle, 'tests.tsv'), 'w') do |manifest|
  tests.each do |test|
    name = test.fetch('name').tr(' ', '-')
    abort "Unsupported test metadata: #{name}" unless name.match?(/\A[a-z0-9-]+\z/) &&
      !names.include?(name) && test.fetch('cmd').size == 1 && test['timeout'] == 30 &&
      test['protocol'] == 'exitcode' && test['workdir'].nil?
    names << name
    input = File.realpath(test.fetch('cmd').first)
    abort "Test escaped source: #{input}" unless input.start_with?(source + '/')
    kind = if input == File.join(source, 'tests/scanner-test.sh')
             'scanner'
           elsif input == File.join(source, 'egl/wayland-egl-symbols-check')
             'symbols'
           else
             header = File.binread(input, 20)
             abort "Expected AArch64 ELF: #{input}" unless header.start_with?("\x7fELF".b) &&
               header.getbyte(4) == 2 && header.getbyte(5) == 1 && header.byteslice(18, 2).unpack1('v') == 183
             'elf'
           end
    relative = "tests/#{File.basename(input)}"
    FileUtils.cp(input, File.join(bundle, relative))
    manifest.puts [name, relative, kind, 30].join("\t")
  end
end
FileUtils.cp(File.join(build, 'tests/exec-fd-leak-checker'), File.join(bundle, 'tests'))
File.open(File.join(bundle, 'runtime.sha256'), 'w') do |manifest|
  %w[bin/wayland-scanner lib/libwayland-client.so lib/libwayland-server.so
     lib/libwayland-cursor.so lib/libwayland-egl.so].each do |file|
    relative = "/usr/pkg/#{file}"
    path = File.join(sysroot, relative)
    manifest.puts "#{Digest::SHA256.file(path).hexdigest}  #{relative}"
  end
end
File.open(File.join(bundle, 'artifacts.sha256'), 'w') do |manifest|
  Dir.glob(File.join(bundle, '**/*')).sort.each do |path|
    next unless File.file?(path)
    next if File.basename(path) == 'artifacts.sha256'
    manifest.puts "#{Digest::SHA256.file(path).hexdigest}  #{path.delete_prefix(bundle + '/')}"
  end
end
puts "Prepared #{tests.size} upstream invocations in #{bundle}"
