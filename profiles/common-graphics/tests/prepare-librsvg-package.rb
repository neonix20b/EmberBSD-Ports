#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted). Embed verified package files in a bounded target consumer.
require 'base64'
require 'digest'
require 'fileutils'
require 'open3'
require 'rubygems/package'
require 'shellwords'
require 'zlib'

abort 'Usage: prepare-librsvg-package.rb CROSS_TOOLS SYSROOT LIBRSVG_PACKAGE ORIGINAL_SOURCE NEW_WORK' unless ARGV.size == 5
tools, sysroot, package, source = ARGV.first(4).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'new absolute work required' unless ARGV.last.start_with?('/') && !File.exist?(work)
abort 'unsafe assembler path' unless [sysroot, source].all? { |p| p.match?(%r{\A/[A-Za-z0-9_./-]+\z}) }
FileUtils.mkdir_p(work)
metadata, status = Open3.capture2('tar', '-xOzf', package, '+CONTENTS')
abort 'wrong renderer package' unless status.success? && metadata.lines.any? { |l| l.strip == '@name librsvg-2.63.2' }
payload = %w[bin/rsvg-convert lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader_svg.so lib/girepository-1.0/Rsvg-2.0.typelib]
package_manifest = []
package_names = []
Zlib::GzipReader.open(package) do |gzip|
  Gem::Package::TarReader.new(gzip) do |tar|
    tar.each do |entry|
      if entry.header.typeflag == 'x'
        # pkg_create declares binary header encoding; no path override is used.
        abort 'unsupported extended package header' unless entry.read == "21 hdrcharset=BINARY\n"
        next
      end
      relative = entry.full_name.sub(%r{\A\./}, '')
      next if relative.start_with?('+') || entry.directory?
      abort 'unsafe archive entry' if relative.start_with?('/') || relative.split('/').include?('..')
      installed = sysroot + '/usr/pkg/' + relative
      if entry.header.typeflag == '2'
        abort "installed symlink differs: #{relative}" unless File.symlink?(installed) && File.readlink(installed) == entry.header.linkname
        package_manifest << "symlink #{File.readlink(installed)}  #{installed}\n"
      elsif entry.file?
        bytes = entry.read
        abort "installed payload differs: #{relative}" unless !File.symlink?(installed) && bytes == File.binread(installed)
        package_manifest << "#{Digest::SHA256.hexdigest(bytes)}  #{installed}\n"
      else
        abort "unexpected archive entry type: #{relative}"
      end
      package_names << relative
    end
  end
end
abort 'incomplete renderer package' unless (payload - package_names).empty? && package_names.include?('lib/librsvg-2.so.2.63.2')
font = source + '/rsvg/tests/resources/Ahem.ttf'
avif = source + '/rsvg/tests/fixtures/reftests/rectangle.avif'
{font => 'b719ecb31c5b21fc573c03f6421c74ac63c271a5a3ff841e34f9705fb94b8448',
 avif => '78333fa68dd739a122be7936b0f82a585a231cf9d863ba1ec6b91248a29afff0'}.each do |path, sha|
  abort "upstream fixture differs: #{path}" unless Digest::SHA256.file(path).hexdigest == sha
end
files = [['rsvg-convert', sysroot + '/usr/pkg/' + payload[0], '0700'],
         ['svg-loader.so', sysroot + '/usr/pkg/' + payload[1], '0600'],
         ['query-loaders', sysroot + '/usr/pkg/bin/gdk-pixbuf-query-loaders', '0700'],
         ['Ahem.ttf', font, '0600'],
         ['font-README.md', source + '/rsvg/tests/resources/README.md', '0600'],
         ['librsvg-AUTHORS', source + '/AUTHORS', '0600'],
         ['librsvg-COPYING.LIB', source + '/COPYING.LIB', '0600']]
names = %w[GLib-2.0 GObject-2.0 Gio-2.0 cairo-1.0 GdkPixbuf-2.0 Rsvg-2.0]
typelibs = names.map { |name| [name, sysroot + '/usr/pkg/lib/girepository-1.0/' + name + '.typelib', '0600'] }
header = "struct fixture { const char *name; const unsigned char *start, *end; mode_t mode; };\n"
assembly = ".section .rodata\n"
manifest = package_manifest
[files, typelibs].each_with_index do |group, g|
  group.each_with_index do |(_name, path, _mode), i|
    symbol = "blob_#{g}_#{i}"
    header += "extern const unsigned char #{symbol}_start[], #{symbol}_end[];\n"
    assembly += ".balign 8\n.global #{symbol}_start, #{symbol}_end\n#{symbol}_start:\n.incbin \"#{path}\"\n#{symbol}_end:\n"
    manifest << "#{Digest::SHA256.file(path).hexdigest}  #{path}\n"
  end
  header += "static const struct fixture #{g.zero? ? 'files' : 'typelibs'}[] = {\n"
  group.each_with_index { |(name, _path, mode), i| header += "{\"#{name}\", blob_#{g}_#{i}_start, blob_#{g}_#{i}_end, #{mode}},\n" }
  header += "};\n"
end
svg = "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='10'><image href='data:image/avif;base64,#{Base64.strict_encode64(File.binread(avif))}'/></svg>"
header += "static const char avif_svg[] = #{svg.dump};\n"
header += "static const char text_svg[] = \"<svg xmlns='http://www.w3.org/2000/svg' width='32' height='16'><text x='1' y='12' font-family='Ahem' font-size='10'>XX</text></svg>\";\n"
assembly += ".section .note.GNU-stack,\"\",@progbits\n"
File.write(work + '/librsvg-fixtures.h', header)
File.write(work + '/librsvg-fixtures.S', assembly)
readelf = tools + '/bin/aarch64--netbsd-readelf'
needed = files.first(3).flat_map do |(_name, path, _mode)|
  out, status = Open3.capture2e(readelf, '-h', '-d', path)
  abort "not AArch64 ELF: #{path}" unless status.success? && out.match?(/Machine:.*AArch64/) && out.match?(/Data:.*little endian/)
  out.scan(/\(NEEDED\).*\[([a-zA-Z0-9._+-]+)\]/).flatten
end.uniq.sort
test_source = File.expand_path('librsvg-package.c', __dir__)
includes = %w[include/glib-2.0 lib/glib-2.0/include include/librsvg-2.0 include/gdk-pixbuf-2.0 include/cairo include]
command = [tools + '/bin/aarch64--netbsd-gcc', '--sysroot=' + sysroot,
           '-B' + sysroot + '/usr/pkg/gcc16/lib/gcc/aarch64--netbsd/16.2.0/',
           '-O2', '-Wall', '-Wextra', '-Werror', '-I' + work] + includes.map { |p| '-I' + sysroot + '/usr/pkg/' + p }
command += [test_source, work + '/librsvg-fixtures.S', '-L' + sysroot + '/usr/pkg/lib', '-L' + sysroot + '/usr/pkg/gcc16/lib',
            '-Wl,-rpath,/usr/pkg/lib:/usr/pkg/gcc16/lib', '-Wl,-rpath-link,' + sysroot + '/usr/pkg/lib',
            '-lrsvg-2', '-lgdk_pixbuf-2.0', '-lcairo', '-lfontconfig', '-lgirepository-2.0', '-lgobject-2.0', '-lglib-2.0',
            '-Wl,--no-as-needed'] + needed.map { |name| '-l:' + name } + ['-o', work + '/librsvg-package']
File.write(work + '/compile.command', command.shelljoin + "\n")
out, status = Open3.capture2e(*command)
File.write(work + '/compile.log', out)
abort "consumer build failed: #{out}" unless status.success?
out, status = Open3.capture2e(readelf, '-d', work + '/librsvg-package')
abort 'consumer omitted a dynamic provider needed by an embedded tool' unless status.success? && (needed - out.scan(/\(NEEDED\).*\[([^\]]+)\]/).flatten).empty?
manifest += [__FILE__, test_source, package, avif, work + '/librsvg-package'].map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }
File.write(work + '/inputs.sha256', manifest.join)
puts "PASS: all #{package_names.size} package files/links match installation; upstream fixtures verified; target consumer embeds CLI/module/GIR and their dynamic providers"
