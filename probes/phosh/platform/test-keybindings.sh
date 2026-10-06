#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/patched/phosh-0.58.0" >&2
    exit 2
fi

source_dir=$(CDPATH= cd -- "$1" && pwd)
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/phosh-keybindings.XXXXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

cp "$script_dir/test-keybindings.gschema.xml" "$test_dir/"
glib-compile-schemas --strict "$test_dir"

# pkg-config produces compiler argument lists; deliberate word splitting.
# shellcheck disable=SC2046
"${CC:-cc}" -std=gnu11 -Wall -Wextra -Werror -Wno-unused-parameter \
    -I"$source_dir/src" $(pkg-config --cflags gtk+-3.0 gio-unix-2.0) \
    "$script_dir/test-keybindings.c" \
    $(pkg-config --libs gtk+-3.0 gio-unix-2.0) -o "$test_dir/test-keybindings"

GSETTINGS_BACKEND=memory GSETTINGS_SCHEMA_DIR="$test_dir" "$test_dir/test-keybindings"
