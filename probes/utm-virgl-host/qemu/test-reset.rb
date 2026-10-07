#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted isolated QEMU reset acceptance.
require 'json'
require 'socket'
require 'timeout'
require 'digest'

abort 'Usage: test-reset.rb QEMU_WORK RENDERER_WORK KERNEL ROOT_FFS ANGLE_FRAMEWORKS NEW_WORK' unless ARGV.size == 6
qemu, renderer, kernel, root, frameworks, work = ARGV
abort 'Simple absolute paths required' unless ARGV.all? { |p| p.match?(/\A\/[A-Za-z0-9_\/.\-]+\z/) }
["#{qemu}/build/qemu-system-aarch64", kernel, root,
 "#{frameworks}/EGL.framework/EGL", "#{frameworks}/GLESv2.framework/GLESv2"].each do |path|
  abort "Missing input: #{path}" unless File.file?(path) && File.size(path) > 0
end
Dir.mkdir(work)
inputs = [kernel, root, "#{frameworks}/EGL.framework/EGL", "#{frameworks}/GLESv2.framework/GLESv2"]
input_hashes = inputs.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
File.write(File.join(work, 'inputs-sha256.txt'), input_hashes.map { |path, hash| "#{hash}  #{path}\n" }.join)
[[qemu, 'binary-sha256.txt'], [renderer, 'binaries-sha256.txt']].each_with_index do |(dir, file), i|
  abort "Invalid build receipt: #{file}" unless system('shasum', '-a', '256', '-c',
    File.join(dir, file), out: File.join(work, "receipt-#{i}.log"))
end
serial = File.join(work, 'guest.log')
host = File.join(work, 'host.log')
socket_path = File.join(work, 'qmp.sock')
env = {'DYLD_FRAMEWORK_PATH' => frameworks, 'DYLD_LIBRARY_PATH' => "#{renderer}/prefix/lib",
       'DYLD_FALLBACK_LIBRARY_PATH' => nil, 'DYLD_FALLBACK_FRAMEWORK_PATH' => nil,
       'DYLD_INSERT_LIBRARIES' => nil, 'DYLD_PRINT_LIBRARIES' => '1',
       'ANGLE_DEFAULT_PLATFORM' => 'metal', 'VIRGL_LOG_LEVEL' => 'info'}
args = ["#{qemu}/build/qemu-system-aarch64", '-name', 'EmberBSD-reset-isolated',
        '-machine', 'virt,accel=hvf', '-cpu', 'host', '-m', '1024', '-smp', '2',
        '-display', 'cocoa,gl=es', '-serial', "file:#{serial}", '-snapshot',
        '-kernel', kernel, '-append', 'root=ld4a console=plcom0',
        '-drive', "file=#{root},if=none,format=raw,id=root", '-device', 'virtio-blk-pci,drive=root',
        '-device', 'virtio-gpu-gl-pci,ember-classic-lifecycle=on', '-net', 'none',
        '-monitor', 'none', '-qmp', "unix:#{socket_path},server=on,wait=off"]
pid = Process.spawn(env, *args, out: host, err: [:child, :out])
socket = nil
reaped = false
begin
  Timeout.timeout(20) do
    sleep 0.05 until File.socket?(socket_path)
    socket = UNIXSocket.new(socket_path)
    raise 'Missing QMP greeting' unless JSON.parse(socket.gets).key?('QMP')
  end
  request = lambda do |name|
    socket.puts(JSON.generate('execute' => name, 'id' => name))
    Timeout.timeout(20) do
      loop do
        line = socket.gets or raise 'QMP closed before reply'
        message = JSON.parse(line)
        next unless message['id'] == name
        raise "QMP failure: #{message}" unless message.key?('return')
        break
      end
    end
  end
  request.call('qmp_capabilities')
  4.times do |cycle|
    Timeout.timeout(40) do
      loop do
        if Process.waitpid(pid, Process::WNOHANG)
          reaped = true
          raise 'QEMU exited before guest readiness'
        end
        log = File.exist?(serial) ? File.read(serial) : ''
        raise 'Guest hold failed' if log.include?('EMBERGPU_HOLD_FAILED')
        break if log.scan('EMBERGPU_LIVE_BACKING_READY').length == cycle + 1
        sleep 0.05
      end
    end
    puts "PASS: boot #{cycle + 1} holds a mapped live DRM resource"
    request.call(cycle == 3 ? 'quit' : 'system_reset')
  end
  Timeout.timeout(20) { Process.wait(pid) }
  reaped = true
  raise "QEMU failed: #{$?}" unless $?.success?
  log = File.read(host)
  raise 'Metal backend not selected' unless log.include?('ANGLE Metal Renderer: Apple')
  raise 'Renderer did not reinitialize at every boot' unless log.scan('GL strings:').length == 4
  %w[libvirglrenderer.1.dylib libepoxy.0.dylib].each do |lib|
    raise "Selected library not loaded: #{lib}" unless log.include?(File.realpath("#{renderer}/prefix/lib/#{lib}"))
  end
  %w[EGL GLESv2].each do |name|
    path = File.realpath("#{frameworks}/#{name}.framework/#{name}")
    raise "Selected framework not loaded: #{name}" unless log.include?(path)
  end
  raise 'Input disk changed despite snapshot mode' unless Digest::SHA256.file(root).hexdigest == input_hashes[root]
  puts 'PASS: three real resets and final quit with live 2D backing; not guest 3D or in-flight draw acceptance.'
ensure
  socket&.close
  unless reaped
    begin
      Process.kill('TERM', pid)
      Timeout.timeout(5) { Process.wait(pid) }
    rescue Timeout::Error
      Process.kill('KILL', pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      # Already exited; never signal a process group.
    end
  end
end
