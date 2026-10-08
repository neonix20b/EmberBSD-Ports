#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), explicit core input-code dependency regression.
require 'digest'
require 'fileutils'
require 'open3'
abort 'usage: wlroots-input-headers.rb PREPARED_PKGSRC CROSS_MAKECONF WLROOTS_SOURCE CROSS_CC SYSROOT NEW_WORK' unless ARGV.length == 6
tree, conf, source, cc, sysroot = ARGV.first(5).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
make = ENV.fetch('BMAKE', 'bmake')
out,status=Open3.capture2e(make,'-C',tree+'/wayland/wlroots',"MAKECONF=#{conf}",'EMBERBSD_WLROOTS_PROFILE=headless-gles2','show-vars','VARNAMES=PKG_FAIL_REASON BUILD_DEPENDS BUILDLINK_DEPMETHOD.input-headers')
File.write(work+'/closure.log',out)
lines=out.lines.map(&:chomp)
abort 'core header dependency missing from minimal recipe' unless status.success? && lines.length==3 && lines[0].empty? && lines[1].include?('input-headers>=1.31.3:../../devel/input-headers') && lines[2]=='build'
input=source+'/types/wlr_keyboard.c'
abort 'upstream core keyboard no longer includes input codes' unless File.read(input).include?('#include <linux/input-event-codes.h>')
File.write(work+'/codes.c',"#include <linux/input-event-codes.h>\n_Static_assert(KEY_A == 30 && KEY_LEFTSHIFT == 42, \"canonical input codes\");\nint main(void) { return 0; }\n")
command=[cc,"--sysroot=#{sysroot}",'-std=c11','-Werror','-c',work+'/codes.c','-o',work+'/codes.o']
out,status=Open3.capture2e(*command)
File.write(work+'/red.log',out)
abort 'control unexpectedly finds input-code headers in base sysroot' if status.success?
abort 'control failed for another reason' unless out.include?('linux/input-event-codes.h') && out.include?('No such file')
out,status=Open3.capture2e(*command,"-I#{sysroot}/usr/pkg/include")
File.write(work+'/green.log',out)
abort 'selected canonical headers do not compile for the target' unless status.success?
header=File.binread(work+'/codes.o',20)
abort 'wrong target object' unless header.byteslice(0,6)=="\x7fELF\x02\x01" && header.byteslice(18,2).unpack1('v')==183
File.write(work+'/inputs.sha256',[__FILE__,input,conf,cc,sysroot+'/usr/pkg/include/linux/input-event-codes.h',sysroot+'/usr/pkg/include/linux/freebsd/input-event-codes.h'].map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
puts 'PASS: unconditional wlroots core needs input codes; explicit build dependency supplies current target headers (real compile RED/GREEN)'
