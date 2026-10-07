#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted source/production allocation regression.
set -eu
if [ "$#" -ne 3 ]; then
    echo 'Usage: modules-fallocate.sh GCC_16_2_ARCHIVE ORIGINAL_UPSTREAM_PATCH NEW_OUTPUT' >&2
    exit 2
fi
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
archive=$1
upstream=$2
output=$3
case "$output" in /*) ;; *) echo 'Output must be absolute.' >&2; exit 2 ;; esac
[ ! -e "$output" ] && [ ! -L "$output" ] || exit 2
sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
pin() { awk -F '\t' -v component="$1" '$1 == component {print $4}' "$root/profiles/development-toolchain/sources.tsv"; }
[ "$(sha256_file "$archive")" = "$(pin gcc)" ] || { echo 'GCC archive hash differs.' >&2; exit 2; }
[ "$(sha256_file "$upstream")" = "$(pin gcc-modules-fallocate)" ] || { echo 'Upstream patch hash differs.' >&2; exit 2; }
mkdir -p "$output/recipe" "$output/baseline"
base=$(git -C "$root" ls-files --stage upstream/pkgsrc | awk '$1 == "160000" {print $2}')
git -C "$root/upstream/pkgsrc" archive -o "$output/base.tar" "$base" lang/gcc16 lang/gcc16-libs lang/gcc16-libjit
tar -xf "$output/base.tar" -C "$output/recipe"
for delta in pkgsrc-gcc16.2.patch strict-tests.patch gcc-tsvc-netbsd.patch gcc-modules-fallocate.patch; do
    patch -f -N -d "$output/recipe" -p1 -F 0 < "$root/profiles/development-toolchain/patches/$delta" >> "$output/recipe.log" 2>&1
done
grep -qx 'PKGREVISION=[[:space:]]*1' "$output/recipe/lang/gcc16/Makefile"
grep -qx 'PKGREVISION=[[:space:]]*2' "$output/recipe/lang/gcc16-libs/Makefile"
patch_file=$output/recipe/lang/gcc16/patches/patch-gcc_cp_module.cc
cat > "$output/digest" <<'DIGEST'
#!/bin/sh
[ "$1" = SHA1 ] || exit 2
shift
shasum -a 1 "$@" | awk '{print $1}'
DIGEST
chmod +x "$output/digest"
DIGEST="$output/digest" awk -f "$root/upstream/pkgsrc/mk/checksum/checksum.awk" -- -p \
    "$output/recipe/lang/gcc16/distinfo" "$patch_file" > "$output/checksum.log"
tar -xf "$archive" -C "$output/baseline" --strip-components=1 gcc-16.2.0/gcc/cp/module.cc
cp -R "$output/baseline" "$output/upstream"
cp -R "$output/baseline" "$output/final"
patch -f -N -d "$output/upstream" -p1 -F 0 < "$upstream" > "$output/upstream-patch.log" 2>&1
patch -f -N -d "$output/final" -p0 -F 0 < "$patch_file" > "$output/final-patch.log" 2>&1
extract() {
    awk '
        /auto allocate = \[\]\(int fd, off_t offset, off_t length\)/ {count++; take=1}
        take {print}
        take && /^[[:space:]]*};/ {take=0; complete++}
        END {if (count != 1 || complete != 1 || take) exit 1}
    ' "$1" > "$2"
}
for variant in baseline upstream final; do
    extract "$output/$variant/gcc/cp/module.cc" "$output/$variant/allocation.inc"
    "${CXX:-c++}" -std=c++11 -Wall -Wextra -Werror -DHAVE_POSIX_FALLOCATE=1 \
        -I "$output/$variant" "$root/profiles/development-toolchain/tests/modules-allocation.cc" \
        -o "$output/$variant/allocation" > "$output/$variant/compile.log" 2>&1
    status=0
    "$output/$variant/allocation" > "$output/$variant/run.log" 2>&1 || status=$?
    printf '%s\n' "$status" > "$output/$variant/status"
    if [ "$variant" = final ]; then
        [ "$status" = 0 ]
        grep -q '^cases=16 failures=0 ENOTSUP=86 EOPNOTSUPP=45$' "$output/$variant/run.log"
    else
        [ "$status" = 1 ]
        grep -q '^FAIL result=45 ftruncate=0 actual=0' "$output/$variant/run.log"
        grep -q '^PASS result=28 ftruncate=0 actual=0' "$output/$variant/run.log"
    fi
    echo "PASS: $variant production allocation branch status=$status"
done
# No POSIX allocation feature: the exact production ftruncate-only branch.
"${CXX:-c++}" -std=c++11 -Wall -Wextra -Werror -Wno-unused-function \
    -I "$output/final" "$root/profiles/development-toolchain/tests/modules-allocation.cc" \
    -o "$output/final/no-posix" > "$output/final/no-posix-compile.log" 2>&1
"$output/final/no-posix" > "$output/final/no-posix-run.log"
# Fail closed on repeated source application and unexpected extraction shape.
if patch -f -N -d "$output/final" -p0 -F 0 < "$patch_file" > "$output/repeat.log" 2>&1; then exit 1; fi
cat "$output/final/gcc/cp/module.cc" "$output/final/gcc/cp/module.cc" > "$output/duplicate.cc"
if extract "$output/duplicate.cc" "$output/duplicate.inc"; then exit 1; fi
sed '/auto allocate = /d' "$output/final/gcc/cp/module.cc" > "$output/missing.cc"
if extract "$output/missing.cc" "$output/missing.inc"; then exit 1; fi
cp "$patch_file" "$output/corrupt-patch-gcc_cp_module.cc"
printf '\ncorruption\n' >> "$output/corrupt-patch-gcc_cp_module.cc"
sed 's/(patch-gcc_cp_module.cc)/(corrupt-patch-gcc_cp_module.cc)/' \
    "$output/recipe/lang/gcc16/distinfo" > "$output/corrupt-distinfo"
if DIGEST="$output/digest" awk -f "$root/upstream/pkgsrc/mk/checksum/checksum.awk" -- -p \
    "$output/corrupt-distinfo" "$output/corrupt-patch-gcc_cp_module.cc" > "$output/corrupt-checksum.log" 2>&1; then exit 1; fi
sha256_file "$output/final/gcc/cp/module.cc" > "$output/final-source.sha256"
echo 'PASS: exact upstream/source hashes, patch checksum, revisions, unsupported/error paths, ftruncate errors and source negatives'
