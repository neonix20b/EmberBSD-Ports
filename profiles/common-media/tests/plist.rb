# SPDX-License-Identifier: BSD-2-Clause
# Source-derived list checks; native DESTDIR/check-files remains mandatory.
require 'open3'
abort 'Usage: ruby plist.rb PATCHED_SOURCE PLIST ALTERNATIVES' unless ARGV.size == 3
source, plist, alternatives = ARGV
lines = File.readlines(plist, chomp: true)
abort 'Duplicate PLIST entry' unless lines.uniq == lines
libraries = %w[avcodec avdevice avfilter avformat avutil swresample swscale]
headers = libraries.flat_map do |lib|
  text = File.read("#{source}/lib#{lib}/Makefile").gsub(/\\\n/, ' ')
  text.scan(/^(?:HEADERS|BUILT_HEADERS)\s*\+?=\s*(.*)$/).flat_map do |entry|
    entry.first.split.map do |name|
      abort "Unhandled header expression #{name}" unless name.match?(/^[\w.]+\.h$/)
      "include/ffmpeg9/lib#{lib}/#{name}"
    end
  end
end
abort 'Installed header inventory differs' unless headers.sort == lines.grep(/^include\//).sort
libraries.each do |lib|
  text = Dir["#{source}/lib#{lib}/version*.h"].map { |path| File.read(path) }.join("\n")
  numbers = %w[MAJOR MINOR MICRO].map do |part|
    text[/^#define LIB#{lib.upcase}_VERSION_#{part}\s+(\d+)$/, 1] || abort("Missing #{lib} #{part}")
  end
  expected = ['', ".#{numbers.first}", ".#{numbers.join('.')}"]
    .map { |suffix| "lib/ffmpeg9/lib#{lib}.so#{suffix}" }
  abort "Wrong #{lib} SONAME inventory" unless expected.sort == lines.grep(/^lib\/ffmpeg9\/lib#{lib}\.so/).sort
end
checks = {
  /^share\/doc\/ffmpeg9\/.*\.txt$/ => Dir["#{source}/doc/*.txt"].map { |f| "share/doc/ffmpeg9/#{File.basename(f)}" },
  /^share\/ffmpeg9\/examples\/.*\.c$/ => Dir["#{source}/doc/examples/*.c"].map { |f| "share/ffmpeg9/examples/#{File.basename(f)}" }
}
checks.each { |pattern, expected| abort "Inventory differs: #{pattern}" unless expected.sort == lines.grep(pattern).sort }
puts 'PASS: public headers, seven library versions, text documentation and example sources'
File.foreach(alternatives) do |line|
  next if line.strip.empty? || line.start_with?('#')
  _name, target = line.split
  target = target.delete_prefix('@PREFIX@/')
  abort "Uninstalled alternatives target: #{target}" unless lines.include?(target)
end
# Evaluate the production documentation inventory rather than duplicating it.
make = ENV.fetch('GMAKE', 'make')
flags = libraries.map { |lib| "CONFIG_#{lib.upcase}=yes" }
input = "print-manifest:\n\t@printf '%s\\n' $(MANPAGES)\n"
out, status = Open3.capture2e(make, '-r', '-s', '-f', "#{source}/doc/Makefile",
  '-f', '-', 'print-manifest', 'AVPROGS-yes=ffmpeg ffprobe', *flags, stdin_data: input)
abort out unless status.success?
manuals = out.split.map do |path|
  basename = File.basename(path)
  "man/man#{File.extname(path).delete_prefix('.')}/#{basename}"
end
abort 'Production man-page inventory differs from PLIST' unless manuals.sort == lines.grep(/^man\//).sort
puts 'PASS: executable alternatives and production man-page inventory'
