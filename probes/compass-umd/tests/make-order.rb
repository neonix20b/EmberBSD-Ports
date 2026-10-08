#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted regression of the actual upstream Make dependency graph.
require 'fileutils'
require 'open3'
abort 'usage: make-order.rb ORIGINAL_TREE PATCHED_TREE GNU_MAKE NEW_WORK' unless ARGV.length == 4
original, patched, make = ARGV.first(3).map { |p| File.realpath(p) }
work = File.expand_path(ARGV[3])
abort 'work must be new' if File.exist?(work)
FileUtils.mkdir(work)
File.write("#{work}/mkdir", "#!/bin/sh\nsleep 0.1\nexec mkdir \"$@\"\n")
File.write("#{work}/cxx", <<~'SH')
  #!/bin/sh
  while [ "$#" -gt 0 ]; do
      if [ "$1" = -o ]; then shift; output=$1; fi
      shift
  done
  [ -d "$(dirname "$output")" ] || { echo 'DEPENDENCY: object directory missing' >&2; exit 77; }
  : > "$output"
SH
File.write("#{work}/ar", "#!/bin/sh\n: > \"$2\"\n")
%w[mkdir cxx ar].each { |p| File.chmod(0755, "#{work}/#{p}") }
{'original'=>original, 'patched'=>patched}.each do |name, source|
  FileUtils.mkdir_p("#{work}/#{name}/out")
  cmd = [make, '-j2', '-f', "#{source}/Linux/driver/umd/Makefile", 'standard_api',
    'BUILD_TARGET_PLATFORM=hw', 'BUILD_AIPU_VERSION=aipu_all', 'BUILD_UMD_API_TYPE=standard_api',
    "COMPASS_DRV_BTENVAR_UMD_BUILD_DIR=#{work}/#{name}/obj", "BUILD_AIPU_DRV_ODIR=#{work}/#{name}/out",
    'COMPASS_DRV_BTENVAR_UMD_SO_NAME_FULL=test.so', 'COMPASS_DRV_BTENVAR_UMD_A_NAME_FULL=test.a',
    "CXX=#{work}/cxx", "AR=#{work}/ar", "MD=#{work}/mkdir -p"]
  out, err, status = Open3.capture3(*cmd, chdir: "#{source}/Linux/driver/umd")
  File.write("#{work}/#{name}.log", out + err)
  if name == 'original'
    abort 'original race not reproduced' unless !status.success? && err.include?('DEPENDENCY: object directory missing')
  else
    abort 'patched make ordering failed' unless status.success? && Dir.glob("#{work}/#{name}/obj/**/*.o").length == 27
  end
end
puts 'PASS: original dependency race RED; patched 27-object ordering GREEN (compiler/archive stubs, actual Makefiles)'
