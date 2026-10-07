#!/bin/sh
# SPDX-License-Identifier: MIT
# Compile the exact upstream/patched macro against NetBSD's documented prototype.
set -eu
[ "$#" = 2 ] || { echo 'Usage: pthread-signature.sh ABS_LIBIIO_SOURCE ABS_NEW_OUTPUT' >&2; exit 2; }
[ ! -e "$2" ] || exit 2
mkdir "$2"
{
    printf '%s\n' '#undef __APPLE__' '#define __NetBSD__ 1' '#define HAS_PTHREAD_SETNAME_NP 1'
    printf '%s\n' 'int pthread_setname_np(unsigned long, const char *, void *);'
    sed -n '/^#if defined(HAS_PTHREAD_SETNAME_NP)/,/^struct iio_mutex/p' "$1/lock.c" | sed '$d'
    printf '%s\n' 'void check(void) { iio_thrd_create_set_name(0, "rx%%name"); }'
} > "$2/signature.c"
"${CC:-cc}" -Werror -fsyntax-only "$2/signature.c"
echo 'PASS exact libiio thread-name macro against the NetBSD three-argument prototype'
