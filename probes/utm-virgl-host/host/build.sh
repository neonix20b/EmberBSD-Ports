#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted private macOS host build. Upstream uses Python generators.
set -eu
[ "$#" -eq 1 ] || { echo "Usage: $0 PREPARED_ABSOLUTE_WORK" >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) exit 2;; esac
[ "$(uname -s)" = Darwin ] || { echo 'This recipe targets macOS' >&2; exit 1; }
: "${PYTHON:?Set PYTHON to the current host Python executable}"
: "${MESON:?Set MESON to the current host meson.py}"
NINJA=${NINJA:-ninja}
PKG_CONFIG=${PKG_CONFIG:-pkg-config}
CC=${CC:-cc}
JOBS=${JOBS:-2}
case "$JOBS" in ''|*[!0-9]*|0) echo 'JOBS must be positive' >&2; exit 2;; esac
case "$PYTHON" in /*) ;; *) echo 'PYTHON must be an absolute executable path' >&2; exit 2;; esac
[ -x "$PYTHON" ] || exit 2
export CC PKG_CONFIG
[ ! -e "$work/prefix" ] && [ ! -e "$work/epoxy-build" ] && [ ! -e "$work/renderer-build" ] || { echo 'Use a freshly prepared tree' >&2; exit 1; }
(cd "$work" && shasum -a 256 -c source-sha256.txt) > "$work/source-check.log"
# Both upstream env shebangs and Meson find_installation must use this Python.
mkdir "$work/host-bin"
ln -s "$PYTHON" "$work/host-bin/python3"
PATH="$work/host-bin:$PATH"
export PATH
"$PYTHON" -c 'import yaml' # Unmodified upstream renderer format generator dependency.
{
    uname -a
    "$CC" --version
    "$PYTHON" --version
    "$PYTHON" "$MESON" --version
    "$NINJA" --version
    "$PKG_CONFIG" --version
} > "$work/tools.txt"
export PKG_CONFIG_LIBDIR="$work/prefix/lib/pkgconfig"
export PKG_CONFIG_PATH="$work/prefix/lib/pkgconfig"
"$PYTHON" "$MESON" setup "$work/epoxy-build" "$work/epoxy" \
    --prefix="$work/prefix" --buildtype=release --wrap-mode=nodownload \
    -Degl=yes -Dglx=no -Dx11=false -Dtests=false "-Dc_args=-I$work/khronos" > "$work/epoxy-configure.log" 2>&1
"$NINJA" -C "$work/epoxy-build" -j "$JOBS" install > "$work/epoxy-build.log" 2>&1
[ "$("$PKG_CONFIG" --modversion epoxy)" = 1.5.10 ]
"$PYTHON" "$MESON" setup "$work/renderer-build" "$work/renderer" \
    --prefix="$work/prefix" --buildtype=debugoptimized --wrap-mode=nodownload \
    -Dplatforms=egl -Dvideo=false -Dvenus=false -Dneptune=false \
    '-Ddrm-renderers=[]' -Dvtest=false -Dtests=false "-Dc_args=-I$work/khronos" > "$work/renderer-configure.log" 2>&1
"$NINJA" -C "$work/renderer-build" -j "$JOBS" install > "$work/renderer-build.log" 2>&1
nm -gU "$work/prefix/lib/libvirglrenderer.1.dylib" > "$work/renderer-symbols.txt"
for symbol in init poll wait_status; do
    grep -Eq " T _virgl_renderer_ember_classic_${symbol}_v1$" "$work/renderer-symbols.txt"
done
otool -L "$work/prefix/lib/libvirglrenderer.1.dylib" "$work/prefix/lib/libepoxy.0.dylib" > "$work/linked-libraries.txt"
shasum -a 256 "$work/prefix/lib/libvirglrenderer.1.dylib" "$work/prefix/lib/libepoxy.0.dylib" > "$work/binaries-sha256.txt"
(cd "$work" && find prefix -type f -exec shasum -a 256 {} \;) > "$work/installed-sha256.txt"
(cd "$work" && shasum -a 256 renderer-build/config.h) >> "$work/installed-sha256.txt"
printf '%s\n' 'PASS: full private renderer built and linked; runtime acceptance is separate.'
