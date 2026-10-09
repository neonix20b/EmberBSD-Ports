#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), bounded labwc sessions with real virtual USB input.
require 'digest'
require 'json'
require 'fileutils'
require 'open3'
require 'socket'
require 'timeout'
require_relative 'labwc-session-oracle'

abort 'usage: run-labwc-session.rb QEMU_WORK RENDERER_WORK KERNEL ROOT_FFS ANGLE_FRAMEWORKS NEW_WORK' unless ARGV.size == 6
workload = 'labwc-virgl'
abort 'simple absolute paths required' unless ARGV.all? { |p| p.match?(%r{\A/[A-Za-z0-9_./-]+\z}) }
qemu, renderer, kernel, root, frameworks = ARGV.first(5).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be a new absolute path' unless ARGV.last.start_with?('/') && !File.exist?(work) && !File.symlink?(work)
abort 'NEW_WORK parent must be canonical' unless File.realpath(File.dirname(work)) == File.dirname(work)
abort 'NEW_WORK overlaps an input' if [qemu, renderer, kernel, root, frameworks].any? { |p| work == p || work.start_with?(p + '/') || p.start_with?(work + '/') }
abort 'only macOS GPU host is supported' unless RUBY_PLATFORM.include?('darwin')

def hash(path)
  Digest::SHA256.file(path).hexdigest
end

def reserve(path)
  out, status = Open3.capture2('df', '-k', path)
  abort 'free-space check failed' unless status.success? && out.lines.last.split[3].to_i >= 2_199_552
end

reserve(File.dirname(work))
Dir.mkdir(work)
FileUtils.cp(__FILE__, work + '/runner.rb')
FileUtils.cp(File.expand_path('labwc-session-oracle.rb', __dir__), work + '/labwc-session-oracle.rb')
[[qemu, 'binary-sha256.txt'], [renderer, 'source-sha256.txt'],
 [renderer, 'installed-sha256.txt'], [renderer, 'binaries-sha256.txt']].each_with_index do |(directory, manifest), index|
  abort "invalid build receipt: #{manifest}" unless system('shasum', '-a', '256', '-c', directory + '/' + manifest,
    chdir: directory, out: work + "/receipt-#{index}.log", err: [:child, :out])
end
binary = qemu + '/build/qemu-system-aarch64'
framework_files = %w[EGL GLESv2].map { |name| frameworks + '/' + name + '.framework/' + name }
framework_files.each do |path|
  suffix = path.split('/').last(2).join('/')
  rows = File.readlines(renderer + '/native-inputs-sha256.txt').select { |line| line.split.last.end_with?('/' + suffix) }
  abort "missing/ambiguous accepted framework: #{path}" unless rows.length == 1
  abort "framework differs from accepted renderer: #{path}" unless rows.first.split.first == hash(path)
end
libraries = %w[libvirglrenderer.1.dylib libepoxy.0.dylib].map { |name| renderer + '/prefix/lib/' + name }
inputs = [kernel, root, binary, __FILE__, File.expand_path('labwc-session-oracle.rb', __dir__)] + libraries + framework_files
inputs += [qemu + '/binary-sha256.txt'] + %w[source-sha256.txt installed-sha256.txt binaries-sha256.txt native-inputs-sha256.txt].map { |n| renderer + '/' + n }
input_hashes = inputs.to_h { |path| [path, hash(path)] }
File.write(work + '/inputs.sha256', input_hashes.map { |path, sha| "#{sha}  #{path}\n" }.join)
serial, host = work + '/guest.log', work + '/host.log'
env = {'PATH'=>'/usr/bin:/bin', 'DYLD_FRAMEWORK_PATH'=>frameworks,
       'DYLD_LIBRARY_PATH'=>renderer + '/prefix/lib', 'DYLD_PRINT_LIBRARIES'=>'1',
       'ANGLE_DEFAULT_PLATFORM'=>'metal', 'VIRGL_LOG_LEVEL'=>'info'}
args = [binary, '-name', 'EmberBSD-VirGL-draw-isolated',
        '-machine', 'virt,accel=hvf', '-cpu', 'host', '-m', '1024', '-smp', '2',
        '-display', 'cocoa,gl=es', '-serial', 'file:' + serial, '-snapshot', '-no-reboot',
        '-kernel', kernel, '-append', 'root=ld4a console=plcom0',
        '-drive', 'file=' + root + ',if=none,format=raw,id=root',
        '-device', 'virtio-blk-pci,drive=root',
        '-device', 'virtio-gpu-gl-pci,ember-classic-lifecycle=on',
        '-net', 'none', '-monitor', 'none', '-qmp', 'unix:' + work + '/qmp.sock,server=on,wait=off']
args += ['-device', 'qemu-xhci', '-device', 'usb-kbd', '-device', 'usb-mouse']
abort 'QMP socket path too long' if (work + '/qmp.sock').bytesize > 100
File.umask(0077)
File.write(work + '/command.json', JSON.pretty_generate({workload: workload, environment: env, argv: args}) + "\n")
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
reaped = false
pid = nil
code = 124
socket = nil
injected = 0
window_keys = 0
drag_inputs = 0
commands = []
qmp = lambda do |command, arguments|
  request = {execute: command, arguments: arguments}
  commands << request
  socket.puts(JSON.generate(request))
  loop do
    line = Timeout.timeout(3) { socket.gets } or abort 'QMP disconnected'
    reply = JSON.parse(line)
    abort "QMP error: #{reply}" if reply.key?('error')
    break if reply.key?('return')
  end
end
begin

  reserve(work)
  pid = Process.spawn(env, *args, unsetenv_others: true, pgroup: true,
    rlimit_fsize: 64 * 1024 * 1024, out: host, err: [:child, :out])
  deadline = clock.call + 340
  while clock.call < deadline
    result = Process.waitpid2(pid, Process::WNOHANG)
    if result
      reaped = true
      status = result[1]
      code = status.exited? ? status.exitstatus : 128 + status.termsig
      break
    end
    if !socket && File.socket?(work + '/qmp.sock')
      socket = UNIXSocket.new(work + '/qmp.sock')
      greeting = JSON.parse(Timeout.timeout(3) { socket.gets })
      abort 'invalid QMP greeting' unless greeting.key?('QMP')
      qmp.call('qmp_capabilities', {})
    end
    ready = File.file?(serial) ? File.binread(serial).scan(/^READY_INPUT\r?$/).length : 0
    if socket && ready > injected
      abort 'unexpected input request count' unless ready == injected + 1 && ready <= 2
      qmp.call('input-send-event', {events: [
        {type: 'rel', data: {axis: 'x', value: 20}},
        {type: 'rel', data: {axis: 'y', value: 15}}]})
      sleep 0.15
      qmp.call('input-send-event', {events: [{type: 'btn', data: {down: true, button: 'left'}}]})
      sleep 0.15
      qmp.call('input-send-event', {events: [{type: 'btn', data: {down: false, button: 'left'}}]})
      qmp.call('send-key', {keys: [{type: 'qcode', data: 'k'}], 'hold-time': 150})
      injected += 1
    end
    log = File.file?(serial) ? File.binread(serial) : ''.b
    requests = log.scan(/^READY_WINDOW: stage=([1-5])\r?$/).flatten
    if socket && requests.size > window_keys
      stage = requests[window_keys].to_i
      abort 'unexpected shortcut request' unless requests.size == window_keys + 1 && window_keys < 10 && stage == window_keys % 5 + 1
      qmp.call('send-key', {keys: [{type: 'qcode', data: [2, 3].include?(stage) ? 'f10' : 'f11'}], 'hold-time': 150})
      window_keys += 1
    end
    drag_ready = log.scan(/^READY_DRAG\r?$/).size
    if socket && drag_ready > drag_inputs
      abort 'unexpected drag request' unless drag_ready == drag_inputs + 1 && drag_ready <= 2
      inside = false
      60.times do
        qmp.call('input-send-event', {events: [{type: 'rel', data: {axis: 'x', value: 10}}, {type: 'rel', data: {axis: 'y', value: 5}}]})
        sleep 0.05
        current = File.binread(serial).split(/READY_DRAG\r?\n/).last
        position = current.scan(/^DRAG_POINTER: x=([\d.]+) y=([\d.]+)\r?$/).last
        if position && (30..600).cover?(position[0].to_f) && (30..360).cover?(position[1].to_f)
          inside = true
          break
        end
      end
      abort 'pointer did not enter drag window' unless inside
      qmp.call('input-send-event', {events: [{type: 'key', data: {down: true, key: {type: 'qcode', data: 'alt'}}}]})
      sleep 0.15
      qmp.call('input-send-event', {events: [{type: 'btn', data: {down: true, button: 'left'}}]})
      sleep 0.15
      10.times do
        qmp.call('input-send-event', {events: [{type: 'rel', data: {axis: 'x', value: 5}}, {type: 'rel', data: {axis: 'y', value: 3}}]})
        sleep 0.05
      end
      qmp.call('input-send-event', {events: [{type: 'btn', data: {down: false, button: 'left'}}]})
      qmp.call('input-send-event', {events: [{type: 'key', data: {down: false, key: {type: 'qcode', data: 'alt'}}}]})
      sleep 0.2
      qmp.call('send-key', {keys: [{type: 'qcode', data: 'k'}], 'hold-time': 150})
      drag_inputs += 1
    end
    sleep 0.05
  end
ensure
  socket.close if socket
  File.write(work + '/qmp-commands.json', JSON.pretty_generate(commands) + "\n")

  if pid && !reaped
    begin
      Process.kill('TERM', -pid)
      deadline = clock.call + 5
      while clock.call < deadline
        if Process.waitpid(pid, Process::WNOHANG)
          reaped = true
          break
        end
        sleep 0.05
      end
      unless reaped
        Process.kill('KILL', -pid)
        Process.waitpid(pid)
        reaped = true
      end
    rescue Errno::ESRCH, Errno::ECHILD
      reaped = true
    end
  end
  File.write(work + '/qemu-exit.txt', "#{code}\n")
end
abort "QEMU did not exit successfully: #{code}" unless code == 0
host_log, guest_log = File.read(host), File.binread(serial)
abort 'Metal backend not selected' unless host_log.include?('ANGLE Metal Renderer: Apple')
(libraries + framework_files).each do |path|
  abort "accepted image not loaded: #{path}" unless host_log.include?(File.realpath(path))
end
begin
  raise 'interactive injection count' unless window_keys == 10 && drag_inputs == 2
  LabwcSessionOracle.check(guest_log, injected)
rescue RuntimeError => error
  abort error.message
end
input_hashes.each { |path, sha| abort "input changed: #{path}" unless hash(path) == sha }
files = Dir.glob(work + '/**/*').select { |p| File.file?(p) }
abort 'output budget exceeded' if files.sum { |p| File.size(p) } > 100 * 1024 * 1024
File.write(work + '/outputs.sha256', files.sort.map { |path| "#{hash(path)}  #{path.delete_prefix(work + '/')}\n" }.join)
puts "PASS: isolated guest #{workload} workload on the verified Metal host; input FFS unchanged"
puts 'Boundary: no VT switching, sustained run, GPU reset or physical GPU acceptance'
