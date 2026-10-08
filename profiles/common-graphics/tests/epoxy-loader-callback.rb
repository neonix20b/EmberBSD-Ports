#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), execute the actual loader callback body.
require 'digest'
require 'fileutils'
require 'open3'
require 'shellwords'

abort 'usage: epoxy-loader-callback.rb MESA_RENDER_SOURCE NEW_WORK' unless ARGV.length == 2
source = File.realpath(ARGV[0])
work = File.expand_path(ARGV[1])
abort 'NEW_WORK must be new and absolute' unless ARGV[1].start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
text = File.read(source)
callback = text[/static int\nloaded_library\(.*?^}\n/m]
abort 'missing actual loader callback' unless callback
# This host-only data fixture uses the one field read by the callback. It does
# not emulate an ELF loader, package library or target rendering result.
File.write("#{work}/callback.c", <<~C)
  #include <stdio.h>
  #include <stdlib.h>
  #include <string.h>
  struct dl_phdr_info { const char *dlpi_name; };
  #{callback}
  int main(int argc, char **argv) {
      struct dl_phdr_info info;
      int result;
      if (argc != 3) return 2;
      info.dlpi_name = argv[1];
      result = loaded_library(&info, sizeof(info), (void *)"/tmp/consumer");
      printf("callback returned %d\\n", result);
      return result == atoi(argv[2]) ? 0 : 3;
  }
C
cc = Shellwords.split(ENV.fetch('CC', 'cc'))
out, err, status = Open3.capture3(*cc, '-std=c11', '-Wall', '-Wextra', '-Werror', "#{work}/callback.c", '-o', "#{work}/callback-test")
File.write("#{work}/compile.log", out + err)
abort 'callback fixture compile failed' unless status.success?
failed = []
{'base-loader' => ['/libexec/ld.elf_so',0], 'usr-loader' => ['/usr/libexec/ld.elf_so',0],
 'foreign-library' => ['/private/tmp/foreign/libLLVM.so',1]}.each do |name, (path, result)|
  out, err, status = Open3.capture3("#{work}/callback-test", path, result.to_s)
  File.write("#{work}/#{name}.log", out + err)
  valid = status.success? && out.include?("callback returned #{result}\n")
  valid &&= err.include?('unexpected loaded library') if result == 1
  puts "#{valid ? 'PASS' : 'FAIL'}: #{name} returns to iterator caller"
  failed << name unless valid
end
File.write("#{work}/source.sha256", Digest::SHA256.file(source).hexdigest + "  " + source + "\n")
abort "failed callback cases: #{failed.join(', ')}" unless failed.empty?
