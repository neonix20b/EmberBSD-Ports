#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Regress the observed same-SONAME libinput fallback and runtime mixtures.
set -eu
recipe=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
check()
{
    awk -v expected=/selected/lib/libinput.so. -f "$recipe/scripts/check-kwin-loader.awk"
}
good='-linput.10 => /selected/lib/libinput.so.10
-lstdc++.9 => /usr/lib/libstdc++.so.9'
printf '%s\n' "$good" | check
if printf '%s\n' "$good" | sed 's@/selected/@/usr/pkg/@' | check; then
    echo 'Accepted wrong input library' >&2; exit 1
fi
if printf '%s\n' "$good" '-lstdc++.7 => /usr/pkg/gcc15/lib/libstdc++.so.7' | check; then
    echo 'Accepted mixed C++ runtime' >&2; exit 1
fi
if printf '%s\n' "$good" '-lmissing.1 => not found' | check; then
    echo 'Accepted unresolved dependency' >&2; exit 1
fi
if printf '%s\n' '-lstdc++.9 => /usr/lib/libstdc++.so.9' | check; then
    echo 'Accepted absent input library' >&2; exit 1
fi
if printf '%s\n' '-linput.10 => /selected/lib/libinput.so.10' | check; then
    echo 'Accepted absent C++ runtime' >&2; exit 1
fi
echo 'KWin loader contracts passed (6 cases)'
