#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), input and source-body runner refusal checks.
# Shell functions are actual production bodies. Synthetic logs/processes below
# test admission and orchestration only; they are never graphics acceptance.
require 'digest'
require 'fileutils'
require 'open3'
require 'shellwords'

abort 'usage: virgl-draw-runner.rb MESA_BUNDLE EPOXY_BUNDLE SYSROOT NEW_WORK' unless ARGV.length == 4
mesa, epoxy, sysroot = ARGV.first(3).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
runner = File.expand_path('../cross/run-virgl-draw.sh', __dir__)
source = File.read(runner)
abort 'unexpected main entry' unless source.end_with?("\nmain \"$@\"\n")
bodies = work + '/production-functions.sh'
File.write(bodies, source.delete_suffix("\nmain \"$@\"\n"))
checks = 0
check = lambda do |name, expected, *command|
  output, error, status = Open3.capture3(*command)
  text = output + error
  File.write("#{work}/#{name}.log", text)
  okay = expected.nil? ? status.success? : !status.success? && text.include?(expected)
  abort "FAIL: #{name} (#{status.exitstatus})" unless okay
  checks += 1
  puts "PASS: #{name}"
end
verify = ['sh', runner, '--verify-sysroot', mesa, epoxy, sysroot]
check.call('accepted-real-inputs', nil, *verify)

changed = work + '/changed-epoxy'
FileUtils.cp_r(epoxy, changed)
changed_verify = ['sh', runner, '--verify-sysroot', mesa, changed, sysroot]
manifest = changed + '/artifacts.sha256'
original_manifest = File.binread(manifest)
File.open(manifest, 'ab') { |f| f.write("changed\n") }
check.call('manifest-drift', 'Unaccepted bundle manifest', *changed_verify)
File.binwrite(manifest, original_manifest)
elf = changed + '/bin/epoxy-render'
original_elf = File.binread(elf)
File.open(elf, 'ab') { |f| f.write('changed real ELF') }
check.call('consumer-drift', 'Bundle drift: bin/epoxy-render', *changed_verify)
File.binwrite(elf, original_elf)
File.write(changed + '/.unrecorded', 'hidden extra file')
check.call('extra-artifact', 'Unrecorded bundle artifact', *changed_verify)
File.unlink(changed + '/.unrecorded')
File.symlink('source', changed + '/extra-link')
check.call('bundle-symlink', 'Nonregular bundle artifact', *changed_verify)
File.unlink(changed + '/extra-link')

# A private hard-link fixture avoids copying runtime DSOs. Negative writes use
# atomic replacement, so no operation writes through a source sysroot link.
fixture = work + '/sysroot'
paths = %w[installed-files.sha256 runtime-libraries.sha256].flat_map do |name|
  File.readlines(epoxy + '/' + name).map { |line| line.chomp.split(/  /, 2).last }
end.uniq
paths.each do |path|
  destination = fixture + path
  FileUtils.mkdir_p(File.dirname(destination))
  FileUtils.ln(File.realpath(sysroot + path), destination)
end
File.readlines(epoxy + '/installed-links.tsv').each do |line|
  path, target = line.chomp.split("\t", 2)
  FileUtils.rm_f(fixture + path)
  File.symlink(target, fixture + path)
end
fixture_verify = ['sh', runner, '--verify-sysroot', mesa, epoxy, fixture]
check.call('accepted-file-fixture', nil, *fixture_verify)
%w[/usr/pkg/include/epoxy/gl.h /usr/pkg/lib/libLLVM.so.23.1].each_with_index do |path, i|
  expected_hash = Digest::SHA256.file(sysroot + path).hexdigest
  File.write(fixture + path + '.changed', 'replaced installed file')
  File.rename(fixture + path + '.changed', fixture + path)
  check.call("installed-drift-#{i}", i.zero? ? 'Installed drift:' : 'Installed file hash mismatch:', *fixture_verify)
  abort 'source sysroot changed' unless Digest::SHA256.file(sysroot + path).hexdigest == expected_hash
  File.unlink(fixture + path)
  FileUtils.ln(File.realpath(sysroot + path), fixture + path)
end
link = fixture + '/usr/pkg/lib/libepoxy.so'
original_link = File.readlink(link)
File.unlink(link)
File.symlink('./' + original_link, link)
check.call('installed-link-drift', 'Installed link drift:', *fixture_verify)
File.unlink(link)
File.symlink(original_link, link)

run_body = lambda do |name, expected, commands, environment = {}|
  check.call(name, expected, environment, 'sh', '-c', ". #{bodies.shellescape}\n#{commands}")
end
run_body.call('inventory-command-failure', 'Bundle inventory failed',
  "find() { return 17; }; verify_bundle #{epoxy.shellescape} 906215cfd3b9b10580181fd3ea13ef2fe7a82c52cc668302b612e8b5c4f75605")
%w[LD_LIBRARY_PATH LD_PRELOAD LIBGL_DRIVERS_PATH GBM_BACKENDS_PATH MESA_LOADER_DRIVER_OVERRIDE LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER].each do |setting|
  run_body.call("override-#{setting.downcase}", "Runtime override is not permitted: #{setting}",
    "#{setting}=forbidden; check_overrides")
end
logs = work + '/logs'
FileUtils.mkdir_p(logs)
libraries = %w[libepoxy.so.0.0.0 libEGL.so.1.0.0 libGLESv2.so.2.0.0 libgbm.so.1.0.0 libgallium-26.2.4.so libLLVM.so.23.1 libdrm.so.2.134.0]
valid_log = (1..4).map { |i| "Cycle #{i}: EGL 1.5; GL OpenGL ES 3.0; renderer virgl (synthetic fixture)\n" }.join +
  libraries.map { |name| "LOADED: /usr/pkg/lib/#{name}\n" }.join +
  "LOADED: /usr/libexec/ld.elf_so\nPASS: shader rejection, clear, triangle pixels and four EGL lifecycles\n"
body_setup = "root=#{fixture.shellescape}; epoxy=#{epoxy.shellescape}; logs=#{logs.shellescape}"
log_cases = {
  'complete-log-fixture' => [valid_log, nil],
  'software-renderer' => [valid_log.sub('renderer virgl', 'renderer llvmpipe'), 'Missing four VirGL draw cycles'],
  'missing-cycle' => [valid_log.sub(/^Cycle 4:.*\n/, ''), 'Missing four VirGL draw cycles'],
  'missing-consumer-pass' => [valid_log.sub(/^PASS:.*\n/, ''), 'Missing four VirGL draw cycles'],
  'missing-live-gbm' => [valid_log.sub(%r{^LOADED: /usr/pkg/lib/libgbm.*\n}, ''), 'Missing live provider: libgbm.so'],
  'unrecorded-provider' => [valid_log + "LOADED: /usr/pkg/lib/virtio_gpu_gbm.so\n", 'Unrecorded or changed package library:'],
  'foreign-provider' => [valid_log + "LOADED: /tmp/libEGL.so\n", 'Foreign library:']
}
log_cases.each do |name, (text, expected)|
  File.write(logs + '/epoxy-render.log', text)
  run_body.call(name, expected, "#{body_setup}; check_render_log")
end

# Exercise the exact env/timeout/consumer argv and nonzero-status path. The
# stand-in is explicitly a host orchestration fixture, not a target executable.
stand_in = work + '/timeout-fixture'
argv_log = work + '/argv.log'
File.write(stand_in, <<~SH)
  #!/bin/sh
  [ "$#" = 6 ] && [ "$1" = -k ] && [ "$2" = 5 ] && [ "$3" = 60 ] || exit 31
  [ "$4" = #{(epoxy + '/bin/epoxy-render').shellescape} ] && [ "$5" = /dev/dri/renderD128 ] && [ "$6" = virgl ] || exit 32
  [ "${INHERITED_PROBE_SECRET-unset}" = unset ] && [ "$MESA_SHADER_CACHE_DISABLE" = true ] || exit 33
  printf '%s\n' "$@" > #{argv_log.shellescape}
  echo 'EXPECTED: controlled timeout fixture exit 37'
  exit 37
SH
File.chmod(0755, stand_in)
run_body.call('exact-invocation-and-error', nil,
  "#{body_setup}; timeout=#{stand_in.shellescape}; result=0; run_draw || result=$?; " \
  "[ \"$result\" = 37 ] && [ \"$(cat \"$logs/exit-status\")\" = 37 ] && " \
  "grep 'EXPECTED: controlled timeout fixture exit 37' \"$logs/epoxy-render.log\"",
  {'INHERITED_PROBE_SECRET' => 'must-not-reach-child'})
abort 'consumer argv was not recorded' unless File.file?(argv_log)
File.write(work + '/inputs.sha256', [runner, mesa + '/artifacts.sha256', epoxy + '/artifacts.sha256'].map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
FileUtils.rm_r(fixture)
puts "PASS: #{checks} input/orchestration guard cases; no guest code or renderer executed"
