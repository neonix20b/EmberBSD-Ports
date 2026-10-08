#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), actual consumer mode and invocation contracts.
# These host policy fixtures do not simulate DRM, GL or successful presentation.
require 'digest'
require 'fileutils'
require 'open3'
require 'shellwords'

abort 'usage: wlroots-drm-mode.rb BASELINE_C NEW_WORK' unless ARGV.length == 2
baseline = File.realpath(ARGV[0])
work = File.expand_path(ARGV[1])
abort 'NEW_WORK must be new and absolute' unless ARGV[1].start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
owner = File.expand_path('../cross', __dir__)
source = owner + '/wlroots-drm.c'
runner = owner + '/run-wlroots-drm.sh'
cc = ENV.fetch('CC', 'cc')

def function(text, name)
  body = text[/^static (?:const char \*|bool)\n#{name}\([^\n]*\)\n\{\n.*?^\}\n/m]
  abort "missing/ambiguous function: #{name}" unless body && text.scan(/^#{name}\(/).length == 1
  body
end

def fixture(text, original)
  entry = text[/\tsetvbuf\(stdout, NULL, _IOLBF, 0\);\n(.*?)\twlr_log_init\(WLR_DEBUG, NULL\);/m, 1]
  abort 'missing actual pre-session admission' unless entry
  helpers = original ? '' : %w[expected_renderer renderer_matches].map { |n| function(text, n) }.join
  header = <<~C
    #include <stdbool.h>
    #include <stddef.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #{helpers}
    static int admission(int argc, char **argv) {
      const char *expected = NULL;
      (void)expected; (void)argv;
    #{entry}
      return EXIT_SUCCESS;
    }
    static unsigned checks;
    #define CHECK(condition, name) do { checks++; if (!(condition)) { \
      fprintf(stderr, "FAIL: %s\\n", name); return 1; } } while (0)
    static void clear_environment(void) {
      const char *names[] = { "LD_LIBRARY_PATH", "LD_PRELOAD", "LIBGL_DRIVERS_PATH",
        "GBM_BACKENDS_PATH", "MESA_LOADER_DRIVER_OVERRIDE", "GALLIUM_DRIVER",
        "WLR_RENDERER_FORCE_SOFTWARE", "WLR_RENDERER", "WLR_RENDER_DRM_DEVICE",
        "LIBGL_ALWAYS_SOFTWARE", "WLR_RENDERER_ALLOW_SOFTWARE" };
      for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); i++) unsetenv(names[i]);
    }
    int main(void) {
      char *gpu[] = { "wlroots-drm", "virgl", NULL };
      clear_environment();
      CHECK(admission(2, gpu) == 0, "explicit VirGL admission");
  C
  return header + "return 0;\n}\n" if original
  header + <<~C
      char *cpu[] = { "wlroots-drm", "llvmpipe", NULL };
      char *bad[] = { "wlroots-drm", "softpipe", NULL };
      const char *software[] = { "LIBGL_ALWAYS_SOFTWARE", "WLR_RENDERER_ALLOW_SOFTWARE" };
      const char *forbidden[] = { "LD_LIBRARY_PATH", "LD_PRELOAD", "LIBGL_DRIVERS_PATH",
        "GBM_BACKENDS_PATH", "MESA_LOADER_DRIVER_OVERRIDE", "GALLIUM_DRIVER",
        "WLR_RENDERER_FORCE_SOFTWARE", "WLR_RENDERER", "WLR_RENDER_DRM_DEVICE" };
      CHECK(admission(0, gpu) != 0, "zero argc");
      CHECK(admission(3, gpu) != 0, "extra argument");
      CHECK(admission(2, bad) != 0, "unsupported renderer");
      CHECK(admission(1, cpu) != 0, "CPU default requires flags");
      for (size_t i = 0; i < 2; i++) {
        setenv(software[i], "1", 1);
        CHECK(admission(2, gpu) != 0, "VirGL rejects software permission");
        CHECK(admission(1, cpu) != 0, "CPU needs both flags");
        setenv(software[i], "", 1);
        CHECK(admission(2, gpu) != 0, "VirGL rejects empty software flag");
        unsetenv(software[i]);
      }
      setenv(software[0], "1", 1); setenv(software[1], "1", 1);
      CHECK(admission(1, cpu) == 0, "unchanged CPU default");
      CHECK(admission(2, cpu) == 0, "explicit CPU mode");
      CHECK(admission(2, gpu) != 0, "VirGL rejects CPU environment");
      for (size_t i = 0; i < sizeof(forbidden)/sizeof(forbidden[0]); i++) {
        setenv(forbidden[i], "override", 1);
        CHECK(admission(1, cpu) != 0, "CPU rejects override");
        unsetenv(software[0]); unsetenv(software[1]);
        CHECK(admission(2, gpu) != 0, "VirGL rejects override");
        unsetenv(forbidden[i]);
        setenv(software[0], "1", 1); setenv(software[1], "1", 1);
      }
      CHECK(renderer_matches("virgl", "virgl"), "actual VirGL name");
      CHECK(renderer_matches("virgl", "virgl (host)"), "actual VirGL description");
      CHECK(!renderer_matches("virgl", "llvmpipe (LLVM 23)"), "reject software fallback");
      CHECK(!renderer_matches("virgl", "llvmpipe virgl"), "reject contained VirGL string");
      CHECK(!renderer_matches("virgl", "virglfake"), "reject renderer prefix collision");
      CHECK(!renderer_matches("virgl", NULL), "reject absent renderer");
      CHECK(renderer_matches("llvmpipe", "llvmpipe (LLVM 23)"), "actual CPU name");
      CHECK(!renderer_matches("llvmpipe", "virgl"), "CPU refuses VirGL substitution");
      printf("PASS: %u actual C admission/renderer checks; no GL/DRM execution\\n", checks);
      return 0;
    }
  C
end

def command(log, *argv)
  out, err, status = Open3.capture3(*argv)
  File.write(log, out + err)
  [status, out + err]
end

candidate = File.read(source)
cases = {'baseline' => [fixture(File.read(baseline), true), 'explicit VirGL admission'],
         'candidate' => [fixture(candidate, false), nil]}
flag_mutant = candidate.sub('} else if (software != NULL || allowed != NULL) {', '} else if (false) {')
abort 'software mutant did not change source' if flag_mutant == candidate
cases['allow-software-mutant'] = [fixture(flag_mutant, false), 'VirGL rejects software permission']
predicate = function(candidate, 'renderer_matches')
loose = predicate.sub(/return actual != NULL &&.*?;/m, 'return actual != NULL && strlen(actual) + length != 0;')
abort 'renderer mutant did not change source' if loose == predicate
cases['renderer-fallback-mutant'] = [fixture(candidate.sub(predicate, loose), false), 'reject software fallback']
cases.each do |name, (text, expected)|
  path = work + '/' + name
  File.write(path + '.c', text)
  status, = command(path + '-compile.log', cc, '-std=c11', '-D_POSIX_C_SOURCE=200809L',
    '-Wall', '-Wextra', '-Werror', path + '.c', '-o', path)
  abort "compile failed: #{name}" unless status.success?
  status, output = command(path + '.log', path)
  abort "wrong causal result: #{name}" unless expected.nil? ? status.success? : !status.success? && output.include?('FAIL: ' + expected)
  puts "PASS: #{name} #{expected ? 'causal RED' : 'GREEN'}"
end

text = File.read(runner)
modes = text[/^select_renderer\(\).*?^# End of mode functions[^\n]*\n/m]
abort 'missing production shell mode functions' unless modes
File.write(work + '/mode-functions.sh', modes)
%w[llvmpipe virgl].each do |mode|
  timeout = work + '/timeout-' + mode
  software_check = mode == 'llvmpipe' ? '[ "$LIBGL_ALWAYS_SOFTWARE" = 1 ] && [ "$WLR_RENDERER_ALLOW_SOFTWARE" = 1 ]' : '[ "${LIBGL_ALWAYS_SOFTWARE-unset}" = unset ] && [ "${WLR_RENDERER_ALLOW_SOFTWARE-unset}" = unset ]'
  File.write(timeout, <<~SH)
    #!/bin/sh
    [ "$#" = 5 ] && [ "$1" = -k ] && [ "$2" = 5 ] && [ "$3" = 60 ] || exit 31
    [ "$4" = /accepted/bin/wlroots-drm ] && [ "$5" = #{mode} ] || exit 32
    #{software_check} || exit 33
    [ "${LD_PRELOAD-unset}" = unset ] && [ "${INHERITED_FIXTURE-unset}" = unset ] || exit 34
    [ "$LIBSEAT_BACKEND" = seatd ] && [ "$WLR_BACKENDS" = drm,libinput ] && [ "$WLR_DRM_DEVICES" = /dev/dri/card0 ] || exit 35
    [ "$MESA_SHADER_CACHE_DISABLE" = true ] || exit 36
    echo 'PASS: controlled invocation fixture #{mode}'
    exit 17
  SH
  File.chmod(0755, timeout)
  selection = mode == 'llvmpipe' ? 'select_renderer' : 'select_renderer virgl'
  script = "set -eu\n. #{(work + '/mode-functions.sh').shellescape}\nbundle=/accepted; device=/dev/dri/card0; timeout=#{timeout.shellescape}\n#{selection}\nresult=0; run_consumer || result=$?\n[ \"$result\" = 17 ]\n"
  status, output = command(work + '/invocation-' + mode + '.log', {'INHERITED_FIXTURE' => 'remove me'}, 'sh', '-c', script)
  abort "wrong shell invocation: #{mode}" unless status.success? && output.include?('PASS: controlled invocation fixture ' + mode)
  puts "PASS: real shell #{mode} mode, clean environment, exact argv and error propagation"
end
['', 'softpipe'].each_with_index do |name, i|
  status, output = command(work + "/invalid-mode-#{i}.log", 'sh', '-c',
    ". #{(work + '/mode-functions.sh').shellescape}; select_renderer #{name.shellescape}")
  abort 'invalid shell mode passed' unless !status.success? && output.include?('Expected renderer must be')
end
File.write(work + '/inputs.sha256', [__FILE__, baseline, source, runner].map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
puts 'PASS: source-derived C/shell policy only; actual GPU rendering and DRM presentation remain separate'
