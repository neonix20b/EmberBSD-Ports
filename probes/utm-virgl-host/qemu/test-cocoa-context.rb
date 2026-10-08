#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), real QEMU/Cocoa body regression.
require 'digest'
require 'fileutils'
require 'open3'

abort 'usage: test-cocoa-context.rb ACCEPTED_QEMU_SOURCE NEW_WORK' unless ARGV.length == 2
source = File.realpath(ARGV[0])
work = File.expand_path(ARGV[1])
abort 'NEW_WORK must be new and absolute' unless ARGV[1].start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
recipe = File.dirname(__FILE__)
patch = recipe + '/cocoa-context.patch'
fixture = recipe + '/cocoa-context-fixture.c'
cocoa_path = source + '/ui/cocoa.m'
virtio_path = source + '/hw/display/virtio-gpu-virgl.c'
console_path = source + '/ui/console.c'
inputs = [__FILE__, recipe + '/prepare.sh', patch, fixture, cocoa_path,
          virtio_path, console_path, source + '/COPYING']
File.write(work + '/inputs.sha256', inputs.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{File.realpath(p)}\n" }.join)
FileUtils.cp(source + '/COPYING', work)

def function(text, name)
  matches = text.scan(/^static void #{name}\([^;{]*\)\n\{\n.*?^\}\n/m)
  abort "missing/ambiguous production function: #{name}" unless matches.length == 1
  matches.first
end

def command(log, *args, **options)
  out, err, status = Open3.capture3(*args, **options)
  File.write(log, out + err)
  [status, out + err]
end

before = File.read(cocoa_path)
virtio = File.read(virtio_path)
FileUtils.mkdir_p(work + '/patched/ui')
FileUtils.cp(cocoa_path, work + '/patched/ui/cocoa.m')
status, output = command(work + '/patch.log', 'patch', '-f', '-F', '0', '-p1',
  '-d', work + '/patched', stdin_data: File.read(patch))
abort 'patch failed or shifted' unless status.success? && !output.match?(/offset|fuzz|FAILED|Reversed|previously applied|Skipping|malformed/i)
after = File.read(work + '/patched/ui/cocoa.m')
abort 'patch changed unrelated source' unless before.sub(function(before, 'with_gl_view_ctx'),
  function(after, 'with_gl_view_ctx')) == after
status, = command(work + '/duplicate.log', 'patch', '-f', '-F', '0', '-p1',
  '-d', work + '/patched', stdin_data: File.read(patch))
abort 'duplicate patch passed' if status.success?
puts 'PASS: exact patch application, only shared helper changed, duplicate refused'

prepare = File.read(recipe + '/prepare.sh')
guard = prepare[/^# Cocoa display callbacks.*?(?=^\(cd "\$work" && find src)/m]
hash_function = prepare.lines.find { |l| l.start_with?('hash() {') }
abort 'missing actual preparation guards' unless guard && hash_function
%w[original changed-source changed-patch wrong-result].each do |name|
  dir = work + '/prepare-' + name
  FileUtils.mkdir_p(dir + '/src/ui')
  FileUtils.mkdir_p(dir + '/recipe')
  File.write(dir + '/src/ui/cocoa.m', before + (name == 'changed-source' ? "\n/* drift */\n" : ''))
  File.write(dir + '/recipe/cocoa-context.patch', File.read(patch) +
    (name == 'changed-patch' ? "\n# drift\n" : ''))
  body = name == 'wrong-result' ? guard.sub(Digest::SHA256.hexdigest(after), '0' * 64) : guard
  abort 'result mutation missing' if name == 'wrong-result' && body == guard
  File.write(dir + '/check.sh', "set -eu\n#{hash_function}work=$1\nrecipe=$2\n" + body)
  status, output = command(dir + '/result.log', 'sh', dir + '/check.sh', dir, dir + '/recipe')
  expected = {'changed-source' => 'Cocoa baseline mismatch', 'changed-patch' => 'Cocoa patch mismatch',
              'wrong-result' => 'Cocoa result mismatch'}[name]
  abort "preparation guard failed: #{name}" unless expected ? !status.success? && output.include?(expected) : status.success?
end
puts 'PASS: actual preparation block accepts source and rejects source/patch/result drift'

versions = {'baseline' => before, 'fixed' => after}
wrong_read = after.sub('previous_read = eglGetCurrentSurface(EGL_READ)', 'previous_read = eglGetCurrentSurface(EGL_DRAW)')
abort 'wrong-read mutation missing' if wrong_read == after
versions['wrong-read-mutant'] = wrong_read
lost_context = after.sub("if (!eglMakeCurrent(restore_display, previous_draw,\n                            previous_read, previous_context)) {",
  "if ((void)previous_draw, (void)previous_read,\n            !eglMakeCurrent(restore_display, EGL_NO_SURFACE,\n                            EGL_NO_SURFACE, EGL_NO_CONTEXT)) {")
abort 'lost-context mutation missing' if lost_context == after
versions['lost-context-mutant'] = lost_context
checks = 0
versions.each do |name, text|
  dir = work + '/' + name
  Dir.mkdir(dir)
  license = text[/\A\/\*.*?\*\//m] || abort('Cocoa notice missing')
  File.write(dir + '/cocoa-body.h', license + "\n" +
    %w[with_gl_view_ctx cocoa_gl_switch cocoa_gl_update].map { |n| function(text, n) }.join("\n"))
  File.write(dir + '/scanout-body.h', virtio[/\A\/\*.*?\*\//m] + "\n" + function(virtio, 'virgl_cmd_set_scanout'))
  FileUtils.cp(fixture, dir)
  modes = if name == 'baseline'
    {'scanout-enabled' => [0, 'PASS:'], 'scanout-disabled' => [1, 'lost renderer context'],
     'scanout-mode-set-nofb' => [1, 'lost renderer context']}
  elsif name == 'wrong-read-mutant'
    {'egl-previous' => [1, 'previous context tuple was not restored']}
  elsif name == 'lost-context-mutant'
    {'scanout-mode-set-nofb' => [1, 'lost renderer context']}
  else
    %w[scanout-enabled scanout-disabled scanout-mode-set-nofb egl-previous egl-none
      egl-nested cgl-previous cgl-none cgl-nested].to_h { |m| [m, [0, 'PASS:']] }.merge(
      'egl-enter-fail' => [1, 'display EGL context current; switches=1 block_calls=0'],
      'egl-restore-fail' => [1, 'previous EGL context; switches=2 block_calls=1'],
      'cgl-enter-fail' => [1, 'display CGL context current; switches=1 block_calls=0'],
      'cgl-restore-fail' => [1, 'previous CGL context; switches=2 block_calls=1'])
  end
  {'plain' => [], 'sanitized' => %w[-fsanitize=address,undefined -fno-omit-frame-pointer]}.each do |build, flags|
    binary = dir + '/' + build
    status, = command(binary + '-compile.log', ENV.fetch('CC', 'clang'), '-std=c11', '-fblocks',
      '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-unused-function', *flags,
      dir + '/cocoa-context-fixture.c', '-o', binary)
    abort "compile failed: #{binary}" unless status.success?
    modes.each do |mode, (code, expected)|
      status, output = command(dir + '/' + build + '-' + mode + '.log', binary, mode)
      abort "wrong result: #{name}/#{build}/#{mode}" unless status.exitstatus == code && output.include?(expected)
      checks += 1
    end
  end
  puts "PASS: #{name} actual body cases, plain + ASan/UBSan"
end
puts "PASS: #{checks} source-derived cases; EGL/CGL/embedding primitives modeled, no GPU/VM execution"
