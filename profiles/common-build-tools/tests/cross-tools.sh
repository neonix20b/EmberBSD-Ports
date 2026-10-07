#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), verify tool composition and target script paths.
set -eu
[ "$#" = 5 ] || { echo "Usage: $0 GCC_PREFIX OS_TOOLDIR EXPORTED_PKGSRC MAKECONF NEW_WORK" >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
compiler=$1 os_tools=$2 pkgsrc=$3 makeconf=$4 work=$5
bmake=${BMAKE:-bmake}
mkdir "$work"
sh "$root/profiles/common-build-tools/cross/prepare-tools.sh" "$compiler" "$os_tools" "$work/tools"
[ "$("$work/tools/bin/aarch64--netbsd-gcc" -dumpmachine)" = aarch64--netbsd ]
[ "$("$work/tools/bin/aarch64--netbsd-gcc" -dumpfullversion)" = 16.2.0 ]
if sh "$root/profiles/common-build-tools/cross/prepare-tools.sh" "$compiler" "$os_tools" "$work/tools" > "$work/existing.log" 2>&1; then exit 1; fi
grep -q 'Output already exists' "$work/existing.log"
mkdir "$work/missing-os-tools"
if sh "$root/profiles/common-build-tools/cross/prepare-tools.sh" "$compiler" "$work/missing-os-tools" "$work/rejected" > "$work/missing.log" 2>&1; then exit 1; fi
grep -q 'Missing NetBSD host install tool' "$work/missing.log"
[ ! -e "$work/rejected" ]
echo 'PASS: tool composition uses GCC16 and rejects existing output or missing host install tool'
"$bmake" -C "$pkgsrc/devel/m4" MAKECONF="$makeconf" show-vars \
    VARNAMES='PKG_FAIL_REASON INSTALL_INFO TOOLS_SCRIPT.install-info DEPENDS' > "$work/info-present.txt"
[ -z "$(sed -n '1p' "$work/info-present.txt")" ]
[ "$(sed -n '2p' "$work/info-present.txt")" = /usr/bin/install-info ]
[ "$(sed -n '3p' "$work/info-present.txt")" = 'exit 0' ]
if grep -q 'pkg_install-info-' "$work/info-present.txt"; then echo "Unexpected matching output" >&2; exit 1; fi
mkdir "$work/empty-sysroot"
"$bmake" -C "$pkgsrc/devel/m4" MAKECONF="$makeconf" EMBERBSD_CROSS_SYSROOT="$work/empty-sysroot" \
    -v PKG_FAIL_REASON > "$work/info-missing.txt"
grep -q 'install-info:run not supported in cross-compilation' "$work/info-missing.txt"
"$bmake" -C "$pkgsrc/devel/m4" MAKECONF="$makeconf" USE_TOOLS='sh pwd gm4:run' \
    -v PKG_FAIL_REASON > "$work/other-runtime-tool.txt"
grep -q 'gm4:run not supported in cross-compilation' "$work/other-runtime-tool.txt"
echo 'PASS: package scripts select the target install-info; missing and unrelated runtime tools stay rejected'
