#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted). Verify installed packages and embed their target data.
require 'digest'
require 'fileutils'
require 'open3'
require 'shellwords'
abort 'Usage: gdk-pixbuf-prepare.rb CROSS_TOOLS SYSROOT BUILT_SOURCE PACKAGE MIME_PACKAGE NEW_WORK' unless ARGV.size == 6
tools, sysroot, source, package, mime_package = ARGV.first(5).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'new absolute work required' unless ARGV.last.start_with?('/') && !File.exist?(work)
abort 'unsafe assembler path' unless (sysroot + work).match?(%r{\A[A-Za-z0-9_./-]+\z})
FileUtils.mkdir_p(work)
manifest = []
[package, mime_package].each_with_index do |archive, i|
  listing, status = Open3.capture2('tar', '-tzf', archive)
  abort 'invalid archive' unless status.success? && listing.lines.all? { |l| p = l.strip; !p.start_with?('/') && !p.split('/').include?('..') }
  dest = work + "/package-#{i}"
  FileUtils.mkdir_p(dest)
  abort 'extract failed' unless system('tar', '-xzf', archive, '-C', dest)
  expected = i == 0 ? 'gdk-pixbuf2-2.44.8nb2' : 'shared-mime-info-2.5.1'
  abort 'wrong selected package' unless File.readlines(dest + '/+CONTENTS').any? { |l| l.strip == '@name ' + expected }
  count = 0
  Dir.glob(dest + '/**/*').sort.each do |path|
    next if File.directory?(path) || File.basename(path).start_with?('+')
    installed = sysroot + '/usr/pkg/' + path.delete_prefix(dest + '/')
    if File.symlink?(path)
      abort "installed symlink differs: #{installed}" unless File.symlink?(installed) && File.readlink(path) == File.readlink(installed)
    else
      hash = Digest::SHA256.file(path).hexdigest
      abort "installed payload differs: #{installed}" unless hash == Digest::SHA256.file(installed).hexdigest
      manifest << "#{hash}  #{installed}\n"
    end
    count += 1
  end
  puts "PASS: #{expected}: #{count} installed payload files/links match package"
end
prefix = sysroot + '/usr/pkg'
modules = Dir.glob(prefix + '/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-*.so').sort
abort 'expected all 11 dynamic loaders' unless modules.size == 11
assets = modules.map { |p| [File.basename(p), p] }
assets += [['update-mime-database', prefix + '/bin/update-mime-database'],
           ['mime/packages/freedesktop.org.xml', prefix + '/share/mime/packages/freedesktop.org.xml']]
names = %w[GLib-2.0 GObject-2.0 GModule-2.0 Gio-2.0 GLibUnix-2.0 GioUnix-2.0 GIRepository-3.0 GdkPixbuf-2.0 GdkPixdata-2.0]
metadata = names.map { |name| [name, prefix + '/lib/girepository-1.0/' + name + '.typelib'] }
header = "struct blob { const char *path; const unsigned char *start, *end; };\n"
assembly = ".section .rodata\n"
(assets + metadata).each_with_index do |(_name, path), i|
  abort 'missing installed fixture' unless File.size?(path)
  header += "extern const unsigned char asset_#{i}_start[], asset_#{i}_end[];\n"
  assembly += ".balign 8\n.global asset_#{i}_start, asset_#{i}_end\nasset_#{i}_start:\n.incbin \"#{path}\"\nasset_#{i}_end:\n"
  manifest << "#{Digest::SHA256.file(path).hexdigest}  #{path}\n"
end
[['assets', assets, 0], ['typelibs', metadata, assets.size]].each do |name, files, offset|
  header += "static const struct blob #{name}[] = {\n"
  files.each_with_index { |(label, _path), i| header += "{\"#{label}\", asset_#{i + offset}_start, asset_#{i + offset}_end},\n" }
  header += "};\n"
end
cache = File.read(source + '/output/gdk-pixbuf/loaders.cache')
cache_paths = cache.scan(/^"(\/[^"\n]+\.so)"$/).flatten
abort 'cache and installed modules differ' unless cache_paths.map { |p| File.basename(p) }.sort == modules.map { |p| File.basename(p) }.sort
cache_paths.each { |p| cache = cache.gsub(p, '@MODULE_DIR@/' + File.basename(p)) }
header += "static const char cache_template[] = #{cache.dump};\n"
File.write(work + '/gdk-pixbuf-assets.h', header)
File.write(work + '/gdk-pixbuf-assets.S', assembly + ".section .note.GNU-stack,\"\",@progbits\n")
consumer = File.expand_path('gdk-pixbuf-consumer.c', __dir__)
command = [tools + '/bin/aarch64--netbsd-gcc', '--sysroot=' + sysroot,
           '-B' + prefix + '/gcc16/lib/gcc/aarch64--netbsd/16.2.0/', '-O2', '-Wall', '-Wextra', '-Werror',
           '-I' + work, '-I' + prefix + '/include/gdk-pixbuf-2.0', '-I' + prefix + '/include/glib-2.0',
           '-I' + prefix + '/lib/glib-2.0/include', consumer, work + '/gdk-pixbuf-assets.S',
           '-L' + prefix + '/lib', '-L' + prefix + '/gcc16/lib', '-Wl,-rpath,/usr/pkg/lib:/usr/pkg/gcc16/lib',
           '-Wl,-rpath-link,' + prefix + '/lib', '-Wl,--no-as-needed', '-lgdk_pixbuf-2.0',
           '-lgirepository-2.0', '-lgio-2.0', '-lgobject-2.0', '-lglib-2.0', '-ltiff', '-lxml2', '-lstdc++',
           '-o', work + '/gdk-pixbuf-consumer']
File.write(work + '/compile.command', command.shelljoin + "\n")
out, status = Open3.capture2e(*command)
File.write(work + '/compile.log', out)
abort "compile failed: #{out}" unless status.success?
manifest += [__FILE__, consumer, package, mime_package, work + '/gdk-pixbuf-consumer'].map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }
File.write(work + '/inputs.sha256', manifest.uniq.join)
puts 'PASS: installed target loaders, metadata and MIME data embedded; consumer cross-builds'
