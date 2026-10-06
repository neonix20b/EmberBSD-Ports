#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Exercise the executable's real Lua state and installed LGI version module.
set -eu
[ "$#" = 1 ] || { echo 'Usage: sh check-version.sh AWESOME_EXECUTABLE' >&2; exit 2; }
version=$("$1" --version)
if ! printf '%s\n' "$version" | awk '
    /Compiled against Lua 5\.4\.6 \(running with Lua 5\.4\)$/ { lua++ }
    /LGI version: 0\.9\.2$/ { lgi++ }
    END { exit !(lua == 1 && lgi == 1) }
'; then
    printf 'FAIL: incorrect Lua/LGI version fields:\n%s\n' "$version" >&2
    exit 1
fi
printf '%s\nPASS: Lua 5.4 runtime and LGI 0.9.2 version fields.\n' "$version"
