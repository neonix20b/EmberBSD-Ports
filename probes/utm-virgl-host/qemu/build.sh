#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted full macOS QEMU build; no installed app modification.
set -eu
[ "$#" -eq 3 ] || { echo "Usage: $0 PREPARED_QEMU_WORK BUILT_RENDERER_WORK HOST_FDT_PREFIX" >&2; exit 2; }
work=$1 host=$2 fdt=$3
case "$work:$host:$fdt" in /*:/*:/*) ;; *) exit 2;; esac
[ "$(uname -s)" = Darwin ] || exit 2
: "${PYTHON:?Set the absolute current host Python executable}"
case "$PYTHON" in /*) ;; *) exit 2;; esac
NINJA=${NINJA:-ninja}
NINJA=$(command -v "$NINJA")
case "$NINJA" in /*) ;; *) echo 'NINJA must resolve to an absolute executable' >&2; exit 2;; esac
PKG_CONFIG=${PKG_CONFIG:-pkg-config}
CC=${CC:-cc}
JOBS=${JOBS:-6}
case "$JOBS" in ''|*[!0-9]*|0) exit 2;; esac
export CC PKG_CONFIG
[ ! -e "$work/build" ] || { echo 'Use a freshly prepared QEMU tree' >&2; exit 1; }
(cd "$work" && shasum -a 256 -c source-sha256.txt) > "$work/source-check.log"
(cd "$host" && shasum -a 256 -c installed-sha256.txt) > "$work/renderer-install-check.log"
shasum -a 256 -c "$host/binaries-sha256.txt" > "$work/renderer-binary-check.log"
# QEMU otherwise installs its vendored Meson 1.5.0. Consume the prepared common
# 1.12.1 distribution already exposed to this Python, instead of accepting that.
"$PYTHON" -c 'import importlib.metadata as m; assert m.version("meson") == "1.12.1", "Expose the prepared common Meson 1.12.1 to PYTHON"'
export PKG_CONFIG_PATH="$host/prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
mkdir "$work/build"
(cd "$work/build" && "$work/src/configure" --target-list=aarch64-softmmu \
    --python="$PYTHON" --ninja="$NINJA" --disable-download --without-default-features \
    --enable-fdt --enable-hvf --enable-tcg --enable-pixman --enable-opengl \
    --enable-virglrenderer --enable-cocoa --enable-vnc --disable-docs \
    --audio-drv-list= "--extra-cflags=-I$host/khronos -I$fdt/include" \
    "--extra-ldflags=-L$fdt/lib" --prefix="$work/prefix") > "$work/configure.log" 2>&1
"$NINJA" -C "$work/build" -j "$JOBS" qemu-system-aarch64 > "$work/build.log" 2>&1
"$work/build/qemu-system-aarch64" --version > "$work/version.txt"
"$work/build/qemu-system-aarch64" -device virtio-gpu-gl-pci,help > "$work/device-options.txt" 2>&1
grep -q 'ember-classic-lifecycle=<bool>.*default: off' "$work/device-options.txt"
otool -L "$work/build/qemu-system-aarch64" > "$work/linked-libraries.txt"
codesign -d --entitlements - "$work/build/qemu-system-aarch64" > "$work/entitlements.txt" 2>&1
shasum -a 256 "$work/build/qemu-system-aarch64" > "$work/binary-sha256.txt"
printf '%s\n' 'PASS: full QEMU executable linked; guest/runtime acceptance is separate.'
