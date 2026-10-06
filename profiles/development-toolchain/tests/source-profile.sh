#!/bin/sh
# Exercise recipe integration without exporting another full pkgsrc tree.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ember-gcc-profile.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
expected=$(git -C "$root" ls-files --stage -- upstream/pkgsrc | awk '$1 == "160000" { print $2 }')
[ "$(git -C "$root/upstream/pkgsrc" rev-parse HEAD)" = "$expected" ]
git -C "$root/upstream/pkgsrc" archive -o "$work/base.tar" "$expected" \
    lang/gcc16 lang/gcc16-libs lang/gcc16-libjit math/mpcomplex devel/gtexinfo
tar -xf "$work/base.tar" -C "$work"
for delta in pkgsrc-gcc16.2.patch strict-tests.patch current-prerequisites.patch; do
    patch -f -E -d "$work" -p1 -F 0 < "$root/profiles/development-toolchain/patches/$delta"
done
grep -q '16.2.0' "$work/lang/gcc16/version.mk"
grep -q 'gcc-16.2.0.tar.xz' "$work/lang/gcc16/distinfo"
grep -q 'mpc-1.4.1' "$work/math/mpcomplex/Makefile"
grep -q 'texinfo-7.3' "$work/devel/gtexinfo/Makefile"
[ ! -e "$work/lang/gcc16/patches/patch-isl_configure" ]
if grep '^TEST_TARGET=' "$work/lang/gcc16/Makefile" | grep -q '||'; then exit 1; fi
if sh "$root/scripts/prepare-pkgsrc.sh" "$work/unknown" unknown; then exit 1; fi
[ ! -e "$work/unknown" ]
# A second application must fail instead of interactively reversing a patch.
if patch -f -E -d "$work" -p1 -F 0 < \
    "$root/profiles/development-toolchain/patches/pkgsrc-gcc16.2.patch" > "$work/repeat.log" 2>&1; then
    echo 'Repeated patch unexpectedly succeeded.' >&2
    exit 1
fi
echo 'PASS: pinned profile, version/checksum update, no ISL patch, strict tests, repeat rejection'
