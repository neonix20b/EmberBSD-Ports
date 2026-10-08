#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), bounded isolated guest VirGL draw acceptance.
require 'digest'
require 'json'
require 'fileutils'
require 'open3'

abort 'usage: run-guest-draw.rb QEMU_WORK RENDERER_WORK KERNEL ROOT_FFS ANGLE_FRAMEWORKS NEW_WORK' unless ARGV.size == 6
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
inputs = [kernel, root, binary, __FILE__] + libraries + framework_files
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
        '-net', 'none', '-monitor', 'none']
File.write(work + '/command.json', JSON.pretty_generate({environment: env, argv: args}) + "\n")
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
reaped = false
pid = nil
code = 124
begin
  reserve(work)
  pid = Process.spawn(env, *args, unsetenv_others: true, pgroup: true,
    rlimit_fsize: 64 * 1024 * 1024, out: host, err: [:child, :out])
  deadline = clock.call + 120
  while clock.call < deadline
    result = Process.waitpid2(pid, Process::WNOHANG)
    if result
      reaped = true
      status = result[1]
      code = status.exited? ? status.exitstatus : 128 + status.termsig
      break
    end
    sleep 0.05
  end
ensure
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
host_log, guest_log = File.read(host), File.read(serial)
abort 'Metal backend not selected' unless host_log.include?('ANGLE Metal Renderer: Apple')
(libraries + framework_files).each do |path|
  abort "accepted image not loaded: #{path}" unless host_log.include?(File.realpath(path))
end
abort 'guest draw runner failed or never completed' unless guest_log.scan(/^EMBER_VIRGL_EXIT=0\r?$/).length == 1 &&
  guest_log.include?('EMBER_VIRGL_END') && !guest_log.include?('panic:') &&
  guest_log.include?('PASS: installed VirGL shader/triangle readback and four GBM EGL lifecycles on renderD128')
abort 'guest renderer proof missing' unless guest_log.scan(/^Cycle [1-4]: .*renderer virgl.*\r?$/).length == 4 &&
  guest_log.include?('PASS: shader rejection, clear, triangle pixels and four EGL lifecycles')
input_hashes.each { |path, sha| abort "input changed: #{path}" unless hash(path) == sha }
files = Dir.glob(work + '/**/*').select { |p| File.file?(p) }
abort 'output budget exceeded' if files.sum { |p| File.size(p) } > 100 * 1024 * 1024
File.write(work + '/outputs.sha256', files.sort.map { |path| "#{hash(path)}  #{path.delete_prefix(work + '/')}\n" }.join)
puts 'PASS: isolated guest VirGL four-cycle GLES draw on Metal; input FFS unchanged'
puts 'Boundary: no guest 3D reset, fault recovery, visible compositor or sustained-run acceptance'
