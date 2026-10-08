#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), run installed PyYAML's upstream consumers.
require 'digest'
require 'open3'

abort 'usage: yaml-consumer.rb HOST_PREFIX PYYAML_6_0_3_SOURCE NEW_WORK' unless ARGV.length == 3
prefix = File.realpath(ARGV[0])
source = File.realpath(ARGV[1])
work = File.expand_path(ARGV[2])
abort 'NEW_WORK must be new and absolute' unless ARGV[2].start_with?('/') && !File.exist?(work)
python = "#{prefix}/bin/python3.14"
smoke = "#{source}/packaging/build/smoketest.py"
legacy = "#{source}/tests/legacy_tests/test_all.py"
[python, smoke, legacy].each { |path| abort "missing input: #{path}" unless File.file?(path) }
out, err, status = Open3.capture3("#{prefix}/sbin/pkg_info", '-K', "#{prefix}/pkgdb", '-e', 'py314-yaml-6.0.3nb1')
abort "missing selected PyYAML package: #{err}" unless status.success? && out.strip == 'py314-yaml-6.0.3nb1'
Dir.mkdir(work)
inputs = [python, smoke] + Dir.glob("#{source}/tests/legacy_tests/**/*").select { |path| File.file?(path) && !path.include?('/__pycache__/') }
File.write("#{work}/inputs.sha256", inputs.sort.map { |path| "#{Digest::SHA256.file(path).hexdigest}  #{path}\n" }.join)
env = %w[PYTHONHOME PYTHONPATH YAML_TEST_FUNCTIONS YAML_TEST_FILENAMES YAML_TEST_VERBOSE].to_h { |name| [name, nil] }
{ 'smoke' => smoke, 'legacy' => legacy }.each do |name, script|
  out, err, status = Open3.capture3(env, python, '-B', script, chdir: work)
  File.write("#{work}/#{name}.log", out + err)
  abort "upstream #{name} process failed" unless status.success?
  if name == 'smoke'
    abort 'upstream C-extension roundtrip was not exercised' unless out.include?('embedded libyaml version is ') && out.include?('smoke test passed for ')
  else
    # Upstream main() does not propagate test_appliance.run() to sys.exit().
    abort 'upstream legacy cases failed or changed' unless out.match?(/^TESTS: 2609$/) && !out.match?(/^(FAILURES|ERRORS):/)
    puts out.lines.grep(/^Skipped /)
  end
end
puts 'PASS: installed PyYAML C/Python roundtrips and 2609 upstream legacy tests; upstream skips are reported above'
