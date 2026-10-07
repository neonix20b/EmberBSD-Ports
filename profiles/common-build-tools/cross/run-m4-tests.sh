#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), installed GNU M4 with upstream manual examples.
set -eu
[ "$#" = 2 ] || { echo "Usage: $0 PRISTINE_M4_SOURCE NEW_OUTPUT" >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || exit 2
sources=$1 output=$2
for path do case "$path" in /*) ;; *) exit 2 ;; esac; done
[ -f "$sources/checks/check-them" ] && [ -d "$sources/examples" ]
[ ! -e "$output" ] && [ ! -L "$output" ] || exit 2
export PATH=/usr/pkg/bin:/usr/pkg/sbin:/bin:/usr/bin:/sbin:/usr/sbin
unset LD_LIBRARY_PATH LD_PRELOAD M4PATH
pkg_info -e m4-1.4.21
[ "$(command -v gm4)" = /usr/pkg/bin/gm4 ]
mkdir -p "$output"
cd "$output"
uname -a > platform.txt
pkg_admin check m4 > package-integrity.txt
gm4 --version > version.txt
ldd /usr/pkg/bin/gm4 > linkage.txt
[ "$(/usr/pkg/gnu/bin/m4 --version | head -1)" = 'm4 (GNU M4) 1.4.21' ]
# Exercise the installed alias and the complete upstream manual-example suite.
sh "$sources/checks/check-them" -I "$sources/examples" -m gm4 \
    "$sources"/checks/[0-9][0-9][0-9].* "$sources/checks/stackovf.test" > upstream-checks.log 2>&1
# The target package installation must register its Info manual.
grep -q 'm4' /usr/pkg/info/dir
echo 'PASS: installed GNU M4, upstream manual examples, stack-overflow check and Info registration'
