#!/bin/sh
# Compile the real patched manager without Linux headers or a desktop.
set -eu
umask 077
[ "$#" -eq 1 ] || { echo 'Usage: sh test-hks-unavailable.sh PATCHED_PHOSH_SOURCE' >&2; exit 2; }
source_dir=$(CDPATH= cd "$1" && pwd)
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
pkg_config=${PKG_CONFIG:-pkg-config}
compiler=${CC:-cc}
command -v "$pkg_config" >/dev/null
command -v "$compiler" >/dev/null
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/phosh-hks-test.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
printf '%s\n' '#define PHOSH_HAVE_RFKILL 0' > "$build_dir/phosh-config.h"

# pkg-config supplies compiler/linker arguments, not shell code.
flags=$("$pkg_config" --cflags --libs gobject-2.0)
set -f
set -- $flags
"$compiler" -std=gnu11 -Werror=implicit-function-declaration -Werror=return-type \
    -I"$build_dir" -I"$source_dir/src" \
    "$source_dir/src/hks-manager.c" "$script_dir/test-hks-unavailable.c" \
    "$@" -o "$build_dir/test-hks-unavailable"
"$build_dir/test-hks-unavailable"
