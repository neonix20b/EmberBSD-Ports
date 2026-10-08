#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted actual-header ABI compile regression.
require 'fileutils'
require 'open3'
require 'digest'
abort 'usage: uapi-cross.rb ORIGINAL_TREE PATCHED_TREE CXX_WRAPPER NEW_WORK' unless ARGV.length == 4
original, patched, cxx = ARGV.first(3).map { |p| File.realpath(p) }
work = File.expand_path(ARGV[3])
abort 'work must be new' if File.exist?(work)
FileUtils.mkdir_p(work)
owner = File.dirname(File.realpath(__FILE__))
headers = {'ioctl.h'=>'5764a3378f017c826ab55382386c5e477c8c8d34ff026cc9e02cff10f2a23bdb',
           'int-ll64.h'=>'faca16150492e943a43c83e6b3069531dd498ef15dc612fb2051b88f7da83afc'}
headers.each { |p,h| abort "reference drift: #{p}" unless Digest::SHA256.file("#{owner}/upstream/#{p}").hexdigest == h }
uapi = 'Linux/driver/kmd/armchina-npu/include'
old = File.read("#{original}/#{uapi}/armchina_aipu.h")
fresh = File.read("#{patched}/#{uapi}/armchina_aipu.h")
# This entire interval contains every enum/structure declaration, untouched.
region = ->(s) { s[s.index('/*\n * Zhouyi'.gsub('\\n', "\n"))...s.index('/*\n * AIPU IOCTL List'.gsub('\\n', "\n"))] }
abort 'paired struct/enum source changed' unless region.call(old) && region.call(old) == region.call(fresh)
FileUtils.mkdir_p(["#{work}/linux", "#{work}/asm"])
FileUtils.cp("#{owner}/upstream/ioctl.h", "#{work}/linux/ioctl.h")
FileUtils.cp("#{owner}/upstream/int-ll64.h", "#{work}/linux/types.h")
# int-ll64.h includes this but does not use it. Match the asserted LP64 target.
File.write("#{work}/asm/bitsperlong.h", "#define __BITS_PER_LONG 64\n")
def compile(cxx, owner, work, name, includes, *flags, expect: true)
  command = [cxx, '-std=c++14', '-Wall', '-Wextra', '-Werror', "#{owner}/uapi-layout.cpp", *includes, *flags,
             '-o', "#{work}/#{name}"]
  out, err, status = Open3.capture3(*command)
  File.write("#{work}/#{name}.log", out + err)
  if expect
    abort "compile failed: #{name}" unless status.success?
  else
    abort "mutation did not fail causally: #{name}" unless !status.success? && err.include?('static assertion failed')
  end
end
compile(cxx, owner, work, 'original-linux', ["-I#{original}/#{uapi}", "-I#{work}"], '-DREFERENCE_LINUX')
compile(cxx, owner, work, 'native-first', ["-I#{patched}/#{uapi}"], '-DNATIVE_FIRST')
compile(cxx, owner, work, 'native-last', ["-I#{patched}/#{uapi}"])
%w[wrong-direction native-encoding wrong-asid].each do |name|
  dir = "#{work}/#{name}-include"
  FileUtils.mkdir(dir)
  FileUtils.cp(Dir.glob("#{patched}/#{uapi}/armchina_aipu*.h"), dir)
  header = "#{dir}/armchina_aipu.h"
  adapter = "#{dir}/armchina_aipu_linux_uapi.h"
  case name
  when 'wrong-direction'
    text = File.read(adapter).sub('ARMCHINA_LINUX_IOC(2U,', 'ARMCHINA_LINUX_IOC(1U,')
    File.write(adapter, text)
  when 'native-encoding'
    text = File.read(header).sub('ARMCHINA_AIPU_IOR ARMCHINA_LINUX_IOR', 'ARMCHINA_AIPU_IOR _IOR')
    File.write(header, text)
  when 'wrong-asid'
    File.write(header, File.read(header).sub('__u64 asid_base[4]', '__u64 asid_base[2]'))
  end
  compile(cxx, owner, work, name, ["-I#{dir}"], '-DNATIVE_FIRST', expect: false)
end
puts 'PASS: original Linux reference + native-header before/after; 32 fixed commands, 17 size/alignment pairs, 16 offsets; 3 causal mutation failures'
