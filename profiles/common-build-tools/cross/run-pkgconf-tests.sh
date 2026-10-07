#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), installed pkgconf acceptance with upstream tests.
set -eu
[ "$#" = 3 ] || { echo "Usage: $0 PRISTINE_TEST_SOURCES CROSS_BUILT_TEST_BINARIES NEW_OUTPUT" >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || exit 2
sources=$1 tests=$2 output=$3
for path do case "$path" in /*) ;; *) exit 2 ;; esac; done
[ -d "$sources/tests" ] && [ -d "$sources/t" ] && [ -x "$tests/test-runner" ]
[ ! -e "$output" ] && [ ! -L "$output" ] || exit 2
export PATH=/usr/pkg/gcc16/bin:/usr/pkg/bin:/usr/pkg/sbin:/bin:/usr/bin:/sbin:/usr/sbin
unset LD_LIBRARY_PATH LD_PRELOAD PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR
[ "$(/usr/pkg/bin/pkg-config --version)" = 3.0.7 ]
pkg_info -e 'gcc16>=16.2.0nb1'
pkg_info -e pkgconf-3.0.7
mkdir -p "$output"
cd "$output"
uname -a > platform.txt
pkg_admin check pkgconf > package-integrity.txt
ldd /usr/pkg/bin/pkgconf "$tests/test-runner" > linkage.txt
grep -q '/usr/pkg/lib/libpkgconf.so.8' linkage.txt
if grep -q 'libpkgconf.so.7' linkage.txt; then exit 1; fi
failed=0
for api in audit buffer bytecode client dependency fileio fragment license path-utils personality queue serialize tuple variable version; do
    if "$tests/test-api-$api" > "api-$api.log" 2>&1; then
        echo "PASS upstream API: $api"
    else
        echo "FAIL upstream API: $api"; failed=1
    fi
done
for group in basic cli link-abi ordering parser personality solver sbom bomtool spdxtool pccritic symlink sysroot tuple; do
    if "$tests/test-runner" --test-fixtures="$sources/tests" --tool-dir=/usr/pkg/bin "$sources/t/$group" > "cli-$group.log" 2>&1; then
        echo "PASS upstream CLI: $group"
    else
        echo "FAIL upstream CLI: $group"; failed=1
    fi
done
cat > consumer.c <<'SOURCE'
#include <libpkgconf/libpkgconf.h>
#include <stdio.h>
int main(void)
{
    if (pkgconf_compare_version("3.0.7", "3.0.6") <= 0 ||
        pkgconf_compare_version("3.0.7", "3.0.7") != 0)
        return 1;
    puts("installed libpkgconf consumer passed");
    return 0;
}
SOURCE
# pkg-config output is intentionally split into compiler arguments.
/usr/pkg/gcc16/bin/cc -std=c11 -Wall -Wextra -Werror \
    $(/usr/pkg/bin/pkg-config --cflags libpkgconf) consumer.c \
    $(/usr/pkg/bin/pkg-config --libs libpkgconf) -Wl,-rpath,/usr/pkg/lib \
    -o consumer > consumer-build.log 2>&1
./consumer > consumer-run.log
ldd consumer > consumer-linkage.txt
grep -q '/usr/pkg/lib/libpkgconf.so.8' consumer-linkage.txt
echo 'PASS: installed pkg-config builds and links a running C API consumer'
exit "$failed"
