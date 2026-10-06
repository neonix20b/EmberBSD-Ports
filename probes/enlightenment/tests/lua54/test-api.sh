#!/bin/sh
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: sh test-api.sh EFL_SOURCE NEW_TEST_DIRECTORY' >&2; exit 2; }
source=$1
work=$2
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
mkdir "$work"
extract()
{
    awk -v function_name="$2" -v return_type="$3" '
        index($0, function_name "(") == 1 { copy = 1; print return_type }
        copy {
            print
            line = $0
            open = gsub(/\{/, "", line)
            closed = gsub(/\}/, "", line)
            if (open) started = 1
            braces += open - closed
            if (started && braces == 0) exit
        }
    ' "$1"
}
extract "$source/src/lib/edje/edje_lua2.c" _elua_push_name 'static char *' > "$work/edje-scanner.c"
extract "$source/src/lib/edje/edje_lua2.c" _elua_scan_params 'static int' >> "$work/edje-scanner.c"
cp "$recipe/test-api.c" "$work/"
flags=
if [ -f "$source/src/lib/efl/efl_lua_compat.h" ]; then
    cp "$source/src/lib/efl/efl_lua_compat.h" "$work/"
    flags=-DHAVE_EFL_LUA_COMPAT
fi
cc -Wall -Wextra -Werror -O2 $flags $(pkg-config --cflags lua) \
    "$work/test-api.c" -o "$work/test-api" $(pkg-config --libs lua)
"$work/test-api" "$source/src/lib/evas/filters/lua/color.lua"
