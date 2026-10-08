#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), corrupt real bundle inputs before target execution.
require 'digest'
require 'fileutils'
require 'open3'

abort 'usage: mesa-package-bundle.rb BUNDLE SYSROOT NEW_WORK' unless ARGV.length == 3
bundle = File.realpath(ARGV[0])
sysroot = File.realpath(ARGV[1])
work = File.expand_path(ARGV[2])
abort 'NEW_WORK must not exist' if File.exist?(work)
runner = File.expand_path('../cross/run-mesa-package-tests.sh', __dir__)
FileUtils.mkdir_p(work)
out, err, status = Open3.capture3('sh', runner, '--verify-only', bundle)
File.write("#{work}/original.log", out + err)
abort 'original bundle failed its hash check' unless status.success?
puts 'PASS: original complete bundle hashes'
out, err, status = Open3.capture3('sh', runner, '--verify-sysroot', bundle, sysroot)
File.write("#{work}/sysroot.log", out + err)
abort 'original installed package failed its file checks' unless status.success?
puts 'PASS: actual sysroot package payload, symlinks and runtime hashes'

%w[bin/mesa-render runtime-libraries.sha256 fixtures/drirc_home/.drirc].each_with_index do |damaged, index|
  fixture = "#{work}/case-#{index}"
  FileUtils.mkdir_p("#{fixture}/guards")
  # Small fixtures retain the real ELF, runtime manifest and upstream home data.
  %w[bin/mesa-render runtime-libraries.sha256 fixtures/drirc_home/.drirc].each do |name|
    destination = "#{fixture}/#{name}"
    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.cp("#{bundle}/#{name}", destination)
  end
  paths = Dir.glob("#{fixture}/**/*", File::FNM_DOTMATCH).select { |p| File.file?(p) }
  File.write("#{fixture}/artifacts.sha256", paths.sort.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p.delete_prefix(fixture + '/')}\n" }.join)
  File.open("#{fixture}/#{damaged}", 'ab') { |f| f.write("\ncorrupt-input\n") }
  # Fault-injection guards are not target results: neither should be reached.
  %w[uname ldd].each do |tool|
    path = "#{fixture}/guards/#{tool}"
    File.write(path, "#!/bin/sh\nprintf 'unexpected target inspection\\n' > \"$MESA_GUARD_MARKER\"\nexit 92\n")
    File.chmod(0755, path)
  end
  marker = "#{fixture}/unexpected-inspection"
  out, err, status = Open3.capture3({'PATH' => "#{fixture}/guards:#{ENV.fetch('PATH')}", 'MESA_GUARD_MARKER' => marker},
                                  'sh', runner, fixture, "#{fixture}/logs")
  File.write("#{work}/case-#{index}.log", out + err)
  abort "corruption did not fail before target inspection: #{damaged}" unless status.exitstatus == 1 &&
    (out + err).include?("Bundle hash mismatch: #{damaged}") && !File.exist?(marker) && !File.exist?("#{fixture}/logs")
  puts "PASS: modified #{damaged} rejected before uname/ldd/target execution"
end

# Copy no full sysroot: link only actual manifest files into a disposable root.
# Replace a link before writing the damaged config, preserving source bytes.
fixture_root = "#{work}/sysroot-fixture"
paths = %w[mesa-package-files.sha256 runtime-libraries.sha256].flat_map do |name|
  File.readlines("#{bundle}/#{name}").map { |line| line.split.fetch(1) }
end.uniq
paths.each do |path|
  abort 'fixture path escapes /usr/pkg' unless path.start_with?('/usr/pkg/') && !path.split('/').include?('..')
  original, destination = sysroot + path, fixture_root + path
  FileUtils.mkdir_p(File.dirname(destination))
  if File.symlink?(original)
    File.symlink(File.readlink(original), destination)
  else
    File.link(original, destination)
  end
end
out, err, status = Open3.capture3('sh', runner, '--verify-sysroot', bundle, fixture_root)
File.write("#{work}/fixture-original.log", out + err)
abort 'original file fixture failed' unless status.success?
damaged = '/usr/pkg/share/drirc.d/00-mesa-defaults.conf'
destination = fixture_root + damaged
File.unlink(destination)
FileUtils.cp(sysroot + damaged, destination)
File.open(destination, 'ab') { |f| f.write("\n<!-- changed acceptance fixture -->\n") }
out, err, status = Open3.capture3('sh', runner, '--verify-sysroot', bundle, fixture_root)
File.write("#{work}/installed-drirc-drift.log", out + err)
abort 'non-ELF installed drift was accepted' unless status.exitstatus == 1 && (out + err).include?("Installed file hash mismatch: #{damaged}")
puts 'PASS: actual non-ELF package config drift rejected on isolated fixture'
FileUtils.cp(sysroot + damaged, destination)
# An alternative link resolves to identical bytes but must still be rejected.
link = '/usr/pkg/lib/libEGL.so'
File.unlink(fixture_root + link)
File.symlink('./' + File.readlink(sysroot + link), fixture_root + link)
out, err, status = Open3.capture3('sh', runner, '--verify-sysroot', bundle, fixture_root)
File.write("#{work}/installed-link-drift.log", out + err)
abort 'symlink target drift was accepted' unless status.exitstatus == 1 && (out + err).include?("Installed link mismatch: #{link}")
puts 'PASS: changed symlink target rejected even when resolved bytes match'
