#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), execute the real runner loop with shell fixtures.
require 'fileutils'
require 'open3'
require 'shellwords'

abort 'usage: mesa-package-loop.rb RUNNER NEW_WORK' unless ARGV.length == 2
runner = File.realpath(ARGV[0])
work = File.expand_path(ARGV[1])
abort 'NEW_WORK must not exist' if File.exist?(work)
text = File.read(runner)
loader = text[/^check_loader\(\) \{.*?^\}/m]
loop_body = text[/^failures=0\n.*\z/m]
abort 'cannot locate production loader function and loop' unless loader && loop_body
FileUtils.mkdir_p(["#{work}/bundle/bin", "#{work}/logs", "#{work}/tools"])
executable = "#{work}/bundle/bin/test-probe"
File.write(executable, "#!/bin/sh\nprintf 'executed actual fixture path\\n'\n")
File.chmod(0755, executable)
File.write("#{work}/bundle/upstream-tests.tsv", "fixture\ttest-probe\t30\n")
# A loader-output fixture exercises the production parser; it is not ELF proof.
File.write("#{work}/tools/ldd", "#!/bin/sh\nprintf 'libc.so.12 => /usr/lib/libc.so.12\\n'\n")
File.chmod(0755, "#{work}/tools/ldd")
File.write("#{work}/timeout", "#!/bin/sh\n[ \"$1\" = 30 ] || exit 91\nshift\n[ \"$1\" = #{Shellwords.escape(executable)} ] || exit 92\nexec \"$@\"\n")
File.chmod(0755, "#{work}/timeout")
shell = "set -eu\nbundle=#{Shellwords.escape(work + '/bundle')}\nlogs=#{Shellwords.escape(work + '/logs')}\ntimeout=#{Shellwords.escape(work + '/timeout')}\n" + loader + "\n" + loop_body
File.write("#{work}/production-loop.sh", shell)
out, err, status = Open3.capture3({'PATH' => "#{work}/tools:#{ENV.fetch('PATH')}"}, 'sh', "#{work}/production-loop.sh")
File.write("#{work}/loop.log", "Host shell-fixture regression only; no target runtime is being tested.\n" + out + err)
abort 'production loop lost the relative executable name or failed to run the fixture' unless status.success? &&
  File.read("#{work}/logs/fixture.log").include?('executed actual fixture path')
puts 'PASS: production loader function preserves loop command paths (host shell fixtures only)'
