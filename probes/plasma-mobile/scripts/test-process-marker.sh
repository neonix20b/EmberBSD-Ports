#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Reuse the native process-scope regressions for both desktop markers.
set -eu
[ "$(uname -s)" = NetBSD ] || { echo 'Run on EmberBSD/NetBSD.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
[ "$#" -eq 1 ] || { echo 'Usage: test-process-marker.sh NEW_WORK_DIRECTORY' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work directory.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")/../../enlightenment" && pwd)
umask 077
mkdir "$work"
for profile in default plasma; do
    mkdir "$work/$profile"
    cc -std=c99 -D_NETBSD_SOURCE -Wall -Wextra -Werror -O2 \
        "$recipe/tests/process-scope/scope-child.c" -o "$work/$profile/scope-child"
    for test in test-session-processes.sh test-cancellation.sh; do
        if [ "$profile" = plasma ]; then
            sed 's/EMBERBSD_ENLIGHTENMENT_SESSION/EMBERBSD_PLASMA_SESSION/g' \
                "$recipe/tests/process-scope/$test" > "$work/$profile/$test"
        else
            cp "$recipe/tests/process-scope/$test" "$work/$profile/$test"
        fi
    done
done
cc -std=c99 -D_NETBSD_SOURCE -Wall -Wextra -Werror -O2 \
    "$recipe/session-processes.c" -o "$work/default/session-processes"
cc -std=c99 -D_NETBSD_SOURCE -Wall -Wextra -Werror -O2 \
    '-DMARKER="EMBERBSD_PLASMA_SESSION"' \
    "$recipe/session-processes.c" -o "$work/plasma/session-processes"
for profile in default plasma; do
    env -u EMBERBSD_ENLIGHTENMENT_SESSION -u EMBERBSD_PLASMA_SESSION \
        sh "$work/$profile/test-session-processes.sh"
    env -u EMBERBSD_ENLIGHTENMENT_SESSION -u EMBERBSD_PLASMA_SESSION \
        sh "$work/$profile/test-cancellation.sh"
done
