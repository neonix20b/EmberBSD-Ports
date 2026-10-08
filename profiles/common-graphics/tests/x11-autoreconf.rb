#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), exercise actual pkgsrc host-tool wrappers.
require 'fileutils'
require 'open3'

abort 'usage: x11-autoreconf.rb PREPARED_PKGSRC CROSS_MAKECONF LIBXSHMFENCE_SOURCE NEW_WORK' unless ARGV.length == 4
tree, conf, source = ARGV.first(3).map { |path| File.realpath(path) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
Dir.mkdir(work)
make = ENV.fetch('BMAKE', 'bmake')
base = [make, '-C', "#{tree}/x11/libxshmfence", "MAKECONF=#{conf}", "WRKOBJDIR=#{work}/pkgwork"]
names = %w[PKG_FAIL_REASON TOOLBASE PATH TOOLS_PATH.libtoolize TOOLS_DIR]
out, status = Open3.capture2e(*base, 'show-vars', "VARNAMES=#{names.join(' ')}")
File.write("#{work}/selection.log", out)
abort 'actual libxshmfence recipe parse failed' unless status.success? && out.lines.length == names.length
vars = names.zip(out.lines.map(&:chomp)).to_h
abort vars['PKG_FAIL_REASON'] unless vars['PKG_FAIL_REASON'].empty?
out, status = Open3.capture2e(*base, 'override-tools')
File.write("#{work}/tools.log", out)
abort 'pkgsrc tool creation failed' unless status.success?
FileUtils.cp_r(source, "#{work}/source")
# Invoke real upstream autoreconf in the actual pkgsrc PATH. No supplied
# LIBTOOLIZE or host PATH injection may hide the original missing-tool bug.
env = { 'PATH' => vars['PATH'], 'LIBTOOLIZE' => nil }
out, status = Open3.capture2e(env, "#{vars['TOOLS_DIR']}/bin/autoreconf", '-vif', chdir: "#{work}/source")
File.write("#{work}/autoreconf.log", out)
abort 'upstream autoreconf failed in the cross recipe tool environment' unless status.success?
selected = "#{vars['TOOLBASE']}/bin/libtoolize"
abort 'pkgsrc selected a different libtoolize' unless vars['TOOLS_PATH.libtoolize'] == selected && File.realpath("#{vars['TOOLS_DIR']}/bin/libtoolize") == File.realpath(selected)
abort 'upstream libtool inputs were not installed' unless out.include?('running: libtoolize --copy --force') && File.file?("#{work}/source/ltmain.sh")
puts 'PASS: actual pkgsrc tools expose the existing host libtoolize and upstream autoreconf completes'
out, status = Open3.capture2e(*base, 'USE_CROSS_COMPILE=no', 'show-vars', 'VARNAMES=PKG_FAIL_REASON TOOLS_PATH.libtoolize')
File.write("#{work}/native.log", out)
abort 'native recursion acquired the cross-only tool override' unless status.success? && out.lines.map(&:chomp) == ['', '']
puts 'PASS: native Darwin tool dependencies preserve their original libtoolize selection'
