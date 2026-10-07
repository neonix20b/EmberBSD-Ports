#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 1 ] || { echo 'Usage: build-guards.sh ABS_NEW_WORK' >&2; exit 2; }
root=$1
case "$root" in /*) ;; *) exit 2 ;; esac
[ ! -e "$root" ] || exit 2
mkdir "$root"
recipe=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
expect_failure() {
    name=$1; shift
    result=0
    "$@" > "$root/$name.log" 2>&1 || result=$?
    [ "$result" -ne 0 ] || { echo "Unexpected success: $name" >&2; exit 1; }
}
expect_failure relative "$recipe/build.sh" relative
expect_failure existing "$recipe/build.sh" "$root"
expect_failure jobs env HOST_CHECK=1 JOBS=0 "$recipe/build.sh" "$root/jobs"
expect_failure limit env HOST_CHECK=1 BUILD_AS_KIB=invalid "$recipe/build.sh" "$root/limit"
[ ! -e "$root/jobs" ] && [ ! -e "$root/limit" ] || exit 1
mkdir "$root/cache"
printf 'corrupt archive\n' > "$root/cache/libxml2-2.15.4.tar.xz"
expect_failure hash env HOST_CHECK=1 "$recipe/build.sh" "$root/hash" "$root/cache"
grep -q 'Source checksum mismatch' "$root/hash.log"
expect_failure missing-install "$recipe/test.sh" "$root"
echo 'PASS path/existing-work, jobs, explicit memory-limit, source-hash and missing-install guards'
