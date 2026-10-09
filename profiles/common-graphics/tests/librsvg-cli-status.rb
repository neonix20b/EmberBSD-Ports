#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted). Reject process failures as malformed-SVG success.
require 'fileutils'
require 'open3'

abort 'Usage: librsvg-cli-status.rb NEW_WORK' unless ARGV.size == 1
work = File.expand_path(ARGV.first)
abort 'new absolute work required' unless ARGV.first.start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
source = File.read(File.join(__dir__, 'librsvg-package.c'))
check = source[/static void\ncheck\(.*?^\}/m] or abort 'check helper missing'
run = source[/static int\nrun\(.*?^\}/m] or abort 'run helper missing'
predicate = source[/check\((run\(bad_args, NULL\).*?), "CLI rejects malformed SVG[^"\n]*"\);/, 1] or abort 'CLI assertion missing'
harness = <<~C
  #include <sys/types.h>
  #include <sys/wait.h>
  #include <fcntl.h>
  #include <stdio.h>
  #include <stdlib.h>
  #include <unistd.h>
  #{check}
  #{run}
  int main(int argc, char **argv) {
    char *bad_args[] = { "/bin/sh", "-c", argc == 2 ? argv[1] : "exit 0", NULL };
    if (argc == 3) bad_args[0] = "/emberbsd-nonexistent-svg-cli";
    return (#{predicate}) ? 0 : 1;
  }
C
File.write(work + '/status.c', harness)
out, status = Open3.capture2e(ENV.fetch('CC', '/usr/bin/cc'), '-Wall', '-Wextra', '-Werror', work + '/status.c', '-o', work + '/status')
File.write(work + '/compile.log', out)
abort out unless status.success?
cases = { 'malformed exit' => [['exit 1'], true], 'success' => [['exit 0'], false],
          'missing executable' => [['unused', 'missing'], false],
          'terminated process' => [['kill -TERM $$'], false],
          'setup failure' => [['exit 125'], false] }
cases.each do |name, (args, accepted)|
  out, status = Open3.capture2e(work + '/status', *args)
  abort "#{name}: wrong acceptance: #{status.inspect}: #{out}" unless status.success? == accepted
end
old = harness.sub(predicate, 'run(bad_args, NULL) != 0')
abort 'negative control unchanged' if old == harness
File.write(work + '/old.c', old)
out, status = Open3.capture2e(ENV.fetch('CC', '/usr/bin/cc'), work + '/old.c', '-o', work + '/old')
abort out unless status.success?
[['unused', 'missing'], ['kill -TERM $$']].each do |args|
  _out, status = Open3.capture2e(work + '/old', *args)
  abort 'old assertion did not reproduce false acceptance' unless status.success?
end
puts 'PASS: malformed CLI exit accepted; success, missing exec, signal and setup failure rejected; old assertion reproduces both false positives'
