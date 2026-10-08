#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), source-causal xkeyboard-config tool selection.
require 'digest'
require 'fileutils'
require 'open3'
abort 'usage: xkeyboard-tools.rb PREPARED_PKGSRC CROSS_MAKECONF ORIGINAL_MAKEFILE VERIFIED_SOURCE NEW_WORK' unless ARGV.length == 5
tree, conf, original, source = ARGV.first(4).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
make = ENV.fetch('BMAKE', 'bmake')
base = [make, '-C', "#{tree}/x11/xkeyboard-config", "MAKECONF=#{conf}"]
query = lambda do |name, *args|
  out, status = Open3.capture2e(*base, *args, 'show-vars', 'VARNAMES=PKG_FAIL_REASON TOOL_DEPENDS TEST_DEPENDS')
  File.write("#{work}/#{name}.log", out)
  abort "parse failed #{name}" unless status.success? && out.lines.length == 3 && out.lines.first.chomp.empty?
  out.lines.map(&:chomp)
end
before = query.call('original-cross', '-f', original)
after = query.call('adapted-cross')
native = query.call('adapted-native', 'USE_CROSS_COMPILE=no')
abort 'control no longer has the unconditional xkbcomp tool dependency' unless before[1].include?('xkbcomp-[0-9]*:../../x11/xkbcomp')
abort 'cross still requires a test-only tool during package creation' if after[1].include?('xkbcomp-')
abort 'cross tests lost their xkbcomp dependency' unless after[2].include?('xkbcomp-[0-9]*:../../x11/xkbcomp')
abort 'native path changed' unless native[1].include?('xkbcomp-[0-9]*:../../x11/xkbcomp') && native[2].empty?
puts 'PASS: original cross closure requires xkbcomp; adapted cross keeps it only for tests; native path preserved'
meson = Dir.glob("#{source}/**/meson.build")
abort 'unexpected upstream build use of xkbcomp' unless !meson.empty? && meson.none? { |p| File.read(p).include?('xkbcomp') }
test = "#{source}/tests/test_xkb_symbols.py"
abort 'upstream test no longer exercises xkbcomp' unless File.read(test).include?('"xkbcomp",')
puts 'PASS: verified upstream build files do not invoke xkbcomp; the actual symbol test does'
File.write("#{work}/inputs.sha256", [__FILE__, conf, original, "#{tree}/x11/xkeyboard-config/Makefile", test, *meson].map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
puts 'PASS: dependency/source contract only; package build and target keyboard semantics are separate checks'
