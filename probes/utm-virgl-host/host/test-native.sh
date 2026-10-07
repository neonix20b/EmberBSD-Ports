#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted native EGL/Metal acceptance. No installed host changes.
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 BUILT_ABSOLUTE_WORK ANGLE_FRAMEWORK_DIRECTORY" >&2; exit 2; }
work=$1 frameworks=$2
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "$work:$frameworks" in /*:/*) ;; *) echo 'Absolute paths required' >&2; exit 2;; esac
[ "$(uname -s)" = Darwin ] || exit 2
: "${CC:=cc}"
(cd "$work" && shasum -a 256 -c source-sha256.txt) > "$work/native-source-check.log"
(cd "$work" && shasum -a 256 -c installed-sha256.txt) > "$work/native-install-check.log"
shasum -a 256 -c "$work/binaries-sha256.txt" > "$work/native-binary-check.log"
[ -f "$frameworks/EGL.framework/EGL" ] && [ -f "$frameworks/GLESv2.framework/GLESv2" ] || { echo 'Real EGL/GLESv2 frameworks required' >&2; exit 1; }
# No inherited dylib override may silently select another renderer or epoxy.
unset DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH DYLD_INSERT_LIBRARIES DYLD_FALLBACK_FRAMEWORK_PATH
export DYLD_FRAMEWORK_PATH="$frameworks"
"$CC" -std=c11 -Wall -Wextra -Werror -imacros "$work/renderer-build/config.h" \
    -I"$work/prefix/include" -I"$work/prefix/include/virgl" -I"$work/khronos" \
    -I"$work/renderer/src" -I"$work/renderer/src/gallium/include" \
    -I"$work/renderer/src/mesa" -I"$work/renderer/src/mesa/pipe" -I"$work/renderer/src/mesa/compat" \
    "$recipe/native-smoke.c" -L"$work/prefix/lib" -lvirglrenderer -lepoxy -o "$work/native-smoke"
shasum -a 256 "$frameworks/EGL.framework/EGL" "$frameworks/GLESv2.framework/GLESv2" \
    "$work/prefix/lib/libvirglrenderer.1.dylib" "$work/prefix/lib/libepoxy.0.dylib" \
    "$recipe/native-smoke.c" "$recipe/native-decoder.h" "$recipe/native-clear.h" \
    "$work/native-smoke" > "$work/native-inputs-sha256.txt"
otool -L "$work/native-smoke" > "$work/native-linked-libraries.txt"
# Keep failure status and diagnostic log. Lack of GPU access is not PASS/SKIP.
DYLD_PRINT_LIBRARIES=1 "$work/native-smoke" "$work/prefix/lib" "$frameworks" > "$work/native-smoke.log" 2>&1 || { cat "$work/native-smoke.log" >&2; exit 1; }
cat "$work/native-smoke.log"
