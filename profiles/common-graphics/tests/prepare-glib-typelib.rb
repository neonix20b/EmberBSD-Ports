#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted). Embed byte-identical installed package typelibs.
require 'digest'
require 'fileutils'
require 'open3'
require 'shellwords'
abort 'Usage: prepare-glib-typelib.rb CROSS_TOOLS SYSROOT PACKAGE NEW_WORK' unless ARGV.size == 4
tools, sysroot, package = ARGV.first(3).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'new absolute work required' unless ARGV.last.start_with?('/') && !File.exist?(work)
abort 'unsafe assembler input path' unless sysroot.match?(%r{\A/[A-Za-z0-9_./-]+\z})
FileUtils.mkdir_p(work)
source = File.expand_path('glib-typelib.c', __dir__)
metadata, status = Open3.capture2('tar', '-xOzf', package, '+CONTENTS')
abort 'not the selected GLib metadata package' unless status.success? && metadata.lines.any? { |l| l.strip == '@name glib2-introspection-2.90.1nb1' }
names = [%w[GLib 2.0 Bytes], %w[GLibUnix 2.0 FDSourceFunc], %w[GObject 2.0 Object],
         %w[GModule 2.0 Module], %w[Gio 2.0 File], %w[GioUnix 2.0 InputStream], %w[GIRepository 3.0 Repository]]
header = "struct fixture { const char *name, *version, *lookup; const unsigned char *start, *end; };\n"
assembly = ".section .rodata\n"
manifest = []
names.each_with_index do |(name, version, _lookup), i|
  relative = "lib/girepository-1.0/#{name}-#{version}.typelib"
  installed = sysroot + '/usr/pkg/' + relative
  data, status = Open3.capture2('tar', '-xOzf', package, relative, binmode: true)
  abort "installed #{name} differs from package" unless status.success? && data == File.binread(installed)
  manifest << "#{Digest::SHA256.hexdigest(data)}  #{installed}\n"
  header += "extern const unsigned char typelib_#{i}_start[], typelib_#{i}_end[];\n"
  assembly += ".balign 8\n.global typelib_#{i}_start, typelib_#{i}_end\ntypelib_#{i}_start:\n.incbin \"#{installed}\"\ntypelib_#{i}_end:\n"
end
header += "static const struct fixture fixtures[] = {\n"
names.each_with_index { |(name, version, lookup), i| header += "{\"#{name}\", \"#{version}\", \"#{lookup}\", typelib_#{i}_start, typelib_#{i}_end},\n" }
header += "};\n"
assembly += ".section .note.GNU-stack,\"\",@progbits\n"
File.write(work + '/typelibs.h', header)
File.write(work + '/typelibs.S', assembly)
cc = tools + '/bin/aarch64--netbsd-gcc'
command = [cc, '--sysroot=' + sysroot, '-B' + sysroot + '/usr/pkg/gcc16/lib/gcc/aarch64--netbsd/16.2.0/',
           '-O2', '-Wall', '-Wextra', '-Werror', '-I' + work, '-I' + sysroot + '/usr/pkg/include/glib-2.0',
           '-I' + sysroot + '/usr/pkg/lib/glib-2.0/include', source, work + '/typelibs.S',
           '-L' + sysroot + '/usr/pkg/lib', '-L' + sysroot + '/usr/pkg/gcc16/lib',
           '-Wl,-rpath,/usr/pkg/lib:/usr/pkg/gcc16/lib', '-Wl,-rpath-link,' + sysroot + '/usr/pkg/lib',
           '-lgirepository-2.0', '-lgobject-2.0', '-lglib-2.0', '-o', work + '/glib-typelib']
File.write(work + '/compile.command', command.shelljoin + "\n")
out, status = Open3.capture2e(*command)
File.write(work + '/compile.log', out)
abort "compile failed: #{out}" unless status.success?
manifest += [source, package, work + '/glib-typelib'].map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }
File.write(work + '/inputs.sha256', manifest.join)
puts 'PASS: installed typelibs match the package and the target consumer cross-builds'
