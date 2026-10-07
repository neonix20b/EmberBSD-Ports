#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# AI-assisted contract invoking the actual upstream ICMPv6 socket constructor.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: test-otbr-infra.sh OPENTHREAD_SOURCE NEW_WORK' >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || { echo 'Native NetBSD/EmberBSD required.' >&2; exit 2; }
source=$1
work=$2
case "$source:$work" in /*:/*) ;; *) exit 2 ;; esac
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$work"
awk '
/^static int BindIcmp6SocketToInterface\(int aSocket, unsigned int aIfIndex\)$/ {active=1; helper++}
/^int InfraNetif::CreateIcmp6Socket\(const char \*aInfraIfName\)$/ {
    sub(/InfraNetif::/, ""); active=1; found++
}
active {print}
active && /^}$/ {active=0}
END {if (found != 1 || helper > 1 || active) exit 2}
' "$source/src/posix/platform/infra_if.cpp" > "$work/constructor.inc"
CXX=${CXX:-/usr/pkg/gcc16/bin/g++}
case "$("$CXX" -dumpfullversion)" in 16.2.*) ;; *) exit 2 ;; esac
"$CXX" -std=c++11 -Wall -Wextra -Werror -I"$work" -I"$source/src" -I"$source/include" \
    "$here/test-otbr-infra.cpp" -o "$work/test-otbr-infra"
echo "Compiled real upstream socket constructor: $work/test-otbr-infra"
echo 'Run this binary as root for raw ICMPv6 socket assertions; it sends no packets.'
