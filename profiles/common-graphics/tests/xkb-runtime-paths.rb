#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), source-causal cross runtime path regression.
require 'digest'
require 'fileutils'
require 'open3'

abort 'usage: xkb-runtime-paths.rb PREPARED_PKGSRC CROSS_MAKECONF ORIGINAL_GENERATED_METADATA CONFIGURED_SOURCE NEW_WORK' unless ARGV.length == 5
tree, conf, original, source = ARGV.first(4).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
make = ENV.fetch('BMAKE', 'bmake')
base = [make, '-C', "#{tree}/x11/libxkbcommon", "MAKECONF=#{conf}"]
run = lambda do |name, *args|
  out, status = Open3.capture2e(*base, *args)
  File.write("#{work}/#{name}.log", out)
  [out, status.success?]
end
out, ok = run.call('cross-selection', 'show-vars', 'VARNAMES=PREFIX CROSS_DESTDIR MESON_ARGS PKGNAME')
abort 'cannot inspect actual cross configuration' unless ok && out.lines.length == 4
prefix, sysroot, args, pkgname = out.lines.map(&:chomp)
abort 'expected the corrected package revision' unless pkgname == 'libxkbcommon-1.13.2nb1'
abort 'invalid target prefix/sysroot' unless prefix.start_with?('/') && sysroot.start_with?('/') && sysroot != '/'
paths = {
  'DFLT_XKB_CONFIG_ROOT' => ['xkb-config-root', 'share/xkeyboard-config-2'],
  'DFLT_XKB_LEGACY_ROOT' => ['xkb-legacy-root', 'share/X11/xkb'],
  'DFLT_XKB_CONFIG_UNVERSIONED_EXTENSIONS_PATH' => ['xkb-config-unversioned-extensions-path', 'share/xkeyboard-config.d'],
  'DFLT_XKB_CONFIG_VERSIONED_EXTENSIONS_PATH' => ['xkb-config-versioned-extensions-path', 'share/xkeyboard-config-2.d']
}
paths.each_value do |option, suffix|
  abort "cross selection missing #{option}" unless args.split.include?("-D#{option}=#{prefix}/#{suffix}")
end
native, ok = run.call('native-selection', 'USE_CROSS_COMPILE=no', 'show-var', 'VARNAME=MESON_ARGS')
abort 'native configuration unexpectedly changed' unless ok && paths.values.none? { |option, _| native.include?("-D#{option}=") }
puts 'PASS: actual cross recipe selects all four target roots; native auto-selection is preserved'

fixture = "#{work}/source"
FileUtils.mkdir_p("#{fixture}/output/meson-private")
config = "#{fixture}/output/config.h"
pc = "#{fixture}/output/meson-private/xkbcommon.pc"
FileUtils.cp("#{original}/config.h", config)
FileUtils.cp("#{original}/xkbcommon.pc", pc)
abort 'original fixture does not reproduce the cross sysroot leak' unless File.read(config).include?(sysroot)
_, ok = run.call('original-metadata-red', "WRKSRC=#{fixture}", 'emberbsd-xkb-runtime-paths')
abort 'original generated metadata was accepted' if ok
puts 'PASS: production guard rejects the original generated cross metadata'

good_config = File.binread("#{source}/output/config.h")
good_pc = File.binread("#{source}/output/meson-private/xkbcommon.pc")
reset = lambda do
  File.binwrite(config, good_config)
  File.binwrite(pc, good_pc)
end
reset.call
_, ok = run.call('configured-metadata-green', "WRKSRC=#{fixture}", 'emberbsd-xkb-runtime-paths')
abort 'actual corrected configuration failed its production guard' unless ok
puts 'PASS: actual newly configured target header and pkg-config metadata pass'
paths.each do |macro, (_, suffix)|
  reset.call
  line = "#define #{macro} \"#{prefix}/#{suffix}\""
  abort "actual header lacks #{macro}" unless good_config.lines.map(&:chomp).include?(line)
  File.write(config, good_config.sub(line, "#define #{macro} \"#{sysroot}#{prefix}/#{suffix}\""))
  _, ok = run.call("reject-#{macro.downcase}", "WRKSRC=#{fixture}", 'emberbsd-xkb-runtime-paths')
  abort "guard accepted drift in #{macro}" if ok
  puts "PASS: production guard rejects drift in #{macro}"
end
reset.call
File.write(pc, good_pc + "\nxkb_probe_path=#{sysroot}#{prefix}/share/xkeyboard-config-2\n")
_, ok = run.call('reject-pkgconfig-sysroot', "WRKSRC=#{fixture}", 'emberbsd-xkb-runtime-paths')
abort 'guard accepted a pkg-config sysroot leak' if ok
puts 'PASS: production guard also rejects target pkg-config metadata drift'
inputs = [__FILE__, conf, "#{tree}/x11/libxkbcommon/Makefile", "#{tree}/x11/libxkbcommon/Makefile.common",
          "#{tree}/x11/libxkbcommon/patches/patch-meson-legacy-root", "#{original}/config.h", "#{original}/xkbcommon.pc",
          "#{source}/output/config.h", "#{source}/output/meson-private/xkbcommon.pc"]
File.write("#{work}/inputs.sha256", inputs.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
puts 'PASS: this checks build metadata and its causal guard; target keymap semantics require a target run'
