#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), real Metal reset acceptance in a new private workdir.
set -eu
[ "$#" = 3 ] || { echo 'Usage: native-reset.sh ACCEPTED_HOST_WORK ANGLE_FRAMEWORKS NEW_WORK' >&2; exit 2; }
case "$1:$2:$3" in /*:/*:/*) ;; *) echo 'Absolute paths required' >&2; exit 2;; esac
[ "$(uname -s)" = Darwin ] || exit 2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
host=$(CDPATH= cd -- "$1" && pwd -P)
frameworks=$(CDPATH= cd -- "$2" && pwd -P)
[ ! -e "$3" ] && [ ! -L "$3" ] || { echo 'NEW_WORK must not exist' >&2; exit 2; }
: "${CC:=cc}"
cc=$(command -v "$CC")
ruby=$(command -v ruby)
case "$cc" in /*) ;; *) echo 'Absolute compiler resolution required' >&2; exit 2;; esac
available=$(df -k "$(dirname -- "$3")" | awk 'END {print $4}')
[ "$available" -ge 2199552 ] || { echo 'Stop: cannot preserve 2 GiB free plus the 100 MiB work budget' >&2; exit 1; }
mkdir "$3"
work=$(CDPATH= cd -- "$3" && pwd -P)
mkdir "$work/source"
cp "$recipe/native-reset.c" "$recipe/native-reset-scene.h" "$recipe/native-draw.h" "$recipe/native-reset.sh" "$work/source/"
(cd "$host" && shasum -a 256 -c source-sha256.txt) > "$work/source-check.log"
(cd "$host" && shasum -a 256 -c installed-sha256.txt) > "$work/installed-check.log"
shasum -a 256 -c "$host/binaries-sha256.txt" > "$work/binary-check.log"
# Preserve the accepted helper and borrowed ANGLE identities from its receipt.
for file in "$work/source/native-draw.h" "$frameworks/EGL.framework/EGL" "$frameworks/GLESv2.framework/GLESv2"; do
    case "$file" in
        */native-draw.h) suffix='/native-draw.h';;
        */EGL.framework/EGL) suffix='/EGL.framework/EGL';;
        *) suffix='/GLESv2.framework/GLESv2';;
    esac
    expected=$(awk -v suffix="$suffix" 'substr($2,length($2)-length(suffix)+1)==suffix {print $1}' "$host/native-inputs-sha256.txt")
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
    [ "$expected" = "$actual" ] || { echo "Accepted input mismatch: $file" >&2; exit 1; }
done
shasum -a 256 "$host/source-sha256.txt" "$host/installed-sha256.txt" "$host/binaries-sha256.txt" \
    "$host/native-inputs-sha256.txt" "$host/renderer-build/config.h" \
    "$host/prefix/lib/libvirglrenderer.1.dylib" "$host/prefix/lib/libepoxy.0.dylib" \
    "$frameworks/EGL.framework/EGL" "$frameworks/GLESv2.framework/GLESv2" "$cc" "$ruby" \
    "$recipe/native-reset.c" "$recipe/native-reset-scene.h" "$recipe/native-reset.sh" "$recipe/native-draw.h" \
    > "$work/inputs.sha256"
"$cc" --version > "$work/compiler.txt"
"$cc" -std=c11 -Wall -Wextra -Werror -imacros "$host/renderer-build/config.h" \
    -I"$host/prefix/include" -I"$host/prefix/include/virgl" -I"$host/khronos" \
    -I"$host/renderer/src" -I"$host/renderer/src/gallium/include" \
    -I"$host/renderer/src/mesa" -I"$host/renderer/src/mesa/pipe" -I"$host/renderer/src/mesa/compat" \
    "$work/source/native-reset.c" -L"$host/prefix/lib" -lvirglrenderer -lepoxy -o "$work/native-reset" \
    > "$work/compile.log" 2>&1 || { cat "$work/compile.log" >&2; exit 1; }
otool -L "$work/native-reset" > "$work/linked-libraries.txt"
# A fresh environment prevents inherited dylib, framework or driver substitutions.
# Ruby supervises only its owned process group, with a monotonic 60+5 second bound.
available=$(df -k "$work" | awk 'END {print $4}')
[ "$available" -ge 2199552 ] || { echo 'Stop: cannot preserve 2 GiB free plus the 100 MiB work budget before GPU execution' >&2; exit 1; }
status=0
"$ruby" - "$work" "$host/prefix/lib" "$frameworks" <<'RUBY' || status=$?
require 'digest'
work, libraries, frameworks = ARGV
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
pid = nil
reaped = false
begin
  pid = Process.spawn({'PATH'=>'/usr/bin:/bin', 'DYLD_FRAMEWORK_PATH'=>frameworks,
                       'DYLD_PRINT_LIBRARIES'=>'1'}, work+'/native-reset', libraries, frameworks,
                      unsetenv_others: true, pgroup: true, rlimit_fsize: 64 * 1024 * 1024, out: work+'/native-reset.log', err: [:child,:out])
  deadline = clock.call + 60
  status = nil
  loop do
    result = Process.waitpid2(pid, Process::WNOHANG)
    if result
      reaped = true
      status = result[1]
      break
    end
    break if clock.call >= deadline
    sleep 0.05
  end
  if status
    code = status.exited? ? status.exitstatus : 128 + status.termsig
  else
    code = 124
    Process.kill('TERM', -pid) rescue Errno::ESRCH
    deadline = clock.call + 5
    loop do
      if Process.waitpid(pid, Process::WNOHANG)
        reaped = true
        break
      end
      break if clock.call >= deadline
      sleep 0.05
    end
  end
ensure
  if pid && !reaped
    Process.kill('KILL', -pid) rescue Errno::ESRCH
    Process.waitpid(pid) rescue Errno::ECHILD
  end
end
File.write(work+'/exit-status', "#{code}\n")
exit code
RUBY
# Preserve failure logs/status too; neither timeout nor lack of Metal is a skip.
shasum -a 256 -c "$work/inputs.sha256" > "$work/final-input-check.log"
(cd "$work" && shasum -a 256 native-reset source/* *.log compiler.txt linked-libraries.txt exit-status inputs.sha256 > outputs.sha256)
[ "$(du -sk "$work" | awk '{print $1}')" -le 102400 ] || { echo 'Work exceeds 100 MiB budget' >&2; exit 1; }
awk '!/^dyld\[/' "$work/native-reset.log"
exit "$status"
