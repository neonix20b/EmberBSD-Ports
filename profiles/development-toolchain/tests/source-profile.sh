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
    lang/gcc16 lang/gcc16-libs lang/gcc16-libjit math/mpcomplex devel/gtexinfo lang/tcl-expect
tar -xf "$work/base.tar" -C "$work"
for delta in pkgsrc-gcc16.2.patch strict-tests.patch current-prerequisites.patch stable-expect.patch gcc-tsvc-netbsd.patch; do
    patch -f -E -d "$work" -p1 -F 0 < "$root/profiles/development-toolchain/patches/$delta"
done
grep -q '16.2.0' "$work/lang/gcc16/version.mk"
grep -q 'gcc-16.2.0.tar.xz' "$work/lang/gcc16/distinfo"
grep -q 'mpc-1.4.1' "$work/math/mpcomplex/Makefile"
grep -q 'texinfo-7.3' "$work/devel/gtexinfo/Makefile"
# Use pkgsrc's own verifier, not a second implementation of its RCS filtering.
# Only SHA1 is needed for patches; shasum provides a portable digest adapter.
cat > "$work/digest" <<'EOF'
#!/bin/sh
[ "$1" = SHA1 ] || exit 2
shift
shasum -a 1 "$@" | awk '{ print $1 }'
EOF
chmod +x "$work/digest"
for recipe in lang/gcc16 math/mpcomplex devel/gtexinfo lang/tcl-expect; do
    DIGEST="$work/digest" awk -f "$root/upstream/pkgsrc/mk/checksum/checksum.awk" \
        -- -p "$work/$recipe/distinfo" "$work/$recipe"/patches/patch-*
done
# Reproduce the review defect: an unfiltered patch hash must be rejected.
raw=$(shasum -a 1 "$work/devel/gtexinfo/patches/patch-configure" | awk '{ print $1 }')
sed "s/^SHA1 (patch-configure) = .*/SHA1 (patch-configure) = $raw/" \
    "$work/devel/gtexinfo/distinfo" > "$work/bad-distinfo"
if DIGEST="$work/digest" awk -f "$root/upstream/pkgsrc/mk/checksum/checksum.awk" \
    -- -p "$work/bad-distinfo" "$work/devel/gtexinfo/patches/patch-configure" \
    > "$work/bad-checksum.log" 2>&1; then
    echo 'pkgsrc unexpectedly accepted the unfiltered patch checksum.' >&2
    exit 1
fi
# These moved/new outputs caught a real 7.2-to-7.3 packaging regression.
for output in Texinfo/CommandsValues.pm Texinfo/ConfigXS.pm \
    Texinfo/Convert/IXIN.pm Texinfo/Convert/TreeElementReadDocBook.pm \
    XSTexinfo/Parsetexi.pm load_txi_modules; do
    grep -qx "share/texi2any/$output" "$work/devel/gtexinfo/PLIST"
done
for output in htmlxref.d/Texinfo_GNU.cnf htmlxref.d/Texinfo_nonGNU.cnf \
    info-hooks/gnu-manuals-locations.dat info-hooks/manual-not-found; do
    grep -qx "share/texinfo/$output" "$work/devel/gtexinfo/PLIST"
done
if grep -qx 'share/texinfo/htmlxref.cnf' "$work/devel/gtexinfo/PLIST"; then exit 1; fi
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
