#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 /path/to/patched/phosh-0.58.0 /path/to/native/build" >&2
    exit 2
fi

source_dir=$(CDPATH= cd -- "$1" && pwd)
build_dir=$(CDPATH= cd -- "$2" && pwd)
backlight_object="$build_dir/src/libphosh-tool.a.p/backlight.c.o"
test -f "$build_dir/phosh-config.h"
test -f "$backlight_object"
test -f "$source_dir/tests/test-backlight.c"
test -f "$source_dir/tests/test-shm.c"

if ! sed -n '/^#define PHOSH_HAVE_LOGIND 0$/p' "$build_dir/phosh-config.h" | \
    grep -q PHOSH_HAVE_LOGIND; then
    echo 'This helper requires the nested build with -Dlogind=disabled.' >&2
    exit 2
fi

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/phosh-native-components.XXXXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

# The real backlight object needs only the shell debug-flags getter.
# Match its enum declaration from this exact source tree, and supply the
# same zero-flags behavior as upstream tests/stubs/phosh.c. This stub exists
# only in the test executable; the application and its object are unchanged.
awk '
    /^typedef enum \{/ { collecting = 1; declaration = "" }
    collecting { declaration = declaration $0 "\n" }
    /^} PhoshShellDebugFlags;/ { print declaration; found = 1; exit }
    /^}/ { collecting = 0 }
    END { if (!found) exit 1 }
' "$source_dir/src/shell-priv.h" > "$test_dir/shell-debug.c"
cat >> "$test_dir/shell-debug.c" <<'EOF'
PhoshShellDebugFlags
phosh_shell_get_debug_flags (void)
{
  return 0;
}
EOF

# pkg-config produces compiler argument lists; deliberate word splitting.
# shellcheck disable=SC2046
"${CC:-cc}" -std=gnu11 -Wall -Wextra -Werror -Wno-unused-parameter \
    -I"$source_dir/src" $(pkg-config --cflags gio-2.0) \
    "$source_dir/tests/test-backlight.c" "$test_dir/shell-debug.c" \
    "$backlight_object" $(pkg-config --libs gio-2.0) -lm \
    -o "$test_dir/test-backlight"
"$test_dir/test-backlight"

# Recompile the real, complete util.c with the native generated config.
# Separate function sections let GNU-compatible linkers discard unrelated
# shell/UI code. No function bodies or platform calls are substituted.
# shellcheck disable=SC2046
"${CC:-cc}" -std=gnu11 -Werror=implicit-function-declaration -Werror=return-type \
    -DGMOBILE_USE_UNSTABLE_API \
    -ffunction-sections -fdata-sections -I"$source_dir/src" -I"$build_dir" \
    $(pkg-config --cflags gtk+-3.0 gio-unix-2.0 gmobile libsoup-3.0) \
    -c "$source_dir/src/util.c" -o "$test_dir/util.o"
# shellcheck disable=SC2046
"${CC:-cc}" -std=gnu11 -Wall -Wextra -Werror -Wno-unused-parameter \
    -I"$source_dir/src" $(pkg-config --cflags gtk+-3.0 gio-unix-2.0) \
    "$source_dir/tests/test-shm.c" "$test_dir/util.o" -Wl,--gc-sections \
    $(pkg-config --libs gio-2.0) -lrt -lm -o "$test_dir/test-shm"
"$test_dir/test-shm"
