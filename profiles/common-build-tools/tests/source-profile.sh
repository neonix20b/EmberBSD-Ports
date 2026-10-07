#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted source and profile integration regression.
set -eu
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo "Usage: $0 VERIFIED_DISTFILES NEW_WORK [python-source|llvm-source]" >&2; exit 2; }
scope=${3:-all}
case "$scope" in all|python-source|llvm-source) ;; *) echo 'Unknown source gate.' >&2; exit 2 ;; esac
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
if [ "$scope" = llvm-source ]; then
    exec sh "$root/profiles/common-build-tools/tests/llvm-source.sh" "$1" "$2"
fi
distfiles=$(CDPATH= cd -- "$1" && pwd)
mkdir "$2"
work=$(CDPATH= cd -- "$2" && pwd)
case "$work:$distfiles" in *[!a-zA-Z0-9_./:-]*) echo 'Use paths without shell metacharacters.' >&2; exit 2 ;; esac
profile=$root/profiles/common-build-tools
cat > "$work/digest" <<'DIGEST'
#!/bin/sh
algorithm=$1
shift
if [ "$#" -eq 0 ]; then
    [ "$algorithm" = SHA1 ] || exit 2
    shasum -a 1 | awk '{print $1}'
    exit
fi
for file do
    case "$algorithm" in
        SHA512) hash=$(shasum -a 512 "$file" | awk '{print $1}') ;;
        BLAKE2s) hash=$("${OPENSSL:-openssl}" dgst -blake2s256 "$file" | awk '{print $NF}') ;;
        *) exit 2 ;;
    esac
    printf '%s (%s) = %s\n' "$algorithm" "$file" "$hash"
done
DIGEST
chmod +x "$work/digest"
export DIGEST=$work/digest
verifier=$root/upstream/pkgsrc/mk/checksum/checksum.awk
while IFS="$(printf '\t')" read -r archive sha url; do
    case "$archive" in ''|'#'*) continue ;; esac
    [ "$scope" != python-source ] || [ "$archive" = Python-3.14.8.tar.xz ] || continue
    [ "$(shasum -a 256 "$distfiles/$archive" | awk '{print $1}')" = "$sha" ]
done < "$profile/sources.tsv"
for pair in 'lang/python314 Python-3.14.8.tar.xz' 'devel/meson meson-1.12.1.tar.gz'; do
    set -- $pair
    [ "$scope" != python-source ] || [ "$1" = lang/python314 ] || continue
    recipe=$profile/recipes/$1 archive=$2
    awk '/^SHA1 \(patch-/ { gsub(/[()]/, "", $2); print $2 }' "$recipe/distinfo" > "$work/required-patches"
    while read -r required; do [ -f "$recipe/patches/$required" ]; done < "$work/required-patches"
    (cd "$distfiles" && awk -f "$verifier" -- "$recipe/distinfo" "$archive")
    recorded=$(awk -v name="($archive)" '$1 == "Size" && $2 == name {print $4}' "$recipe/distinfo")
    [ "$(wc -c < "$distfiles/$archive" | tr -d ' ')" = "$recorded" ]
    awk -f "$verifier" -- -p "$recipe/distinfo" "$recipe"/patches/patch-*
done
# A corrupt archive, unfiltered RCS hash, and absent required patch must fail.
if [ "$scope" = python-source ]; then corrupt=Python-3.14.8.tar.xz; recipe=lang/python314; else
    corrupt=meson-1.12.1.tar.gz; recipe=devel/meson
fi
cp "$distfiles/$corrupt" "$work/$corrupt"
printf x >> "$work/$corrupt"
if (cd "$work" && awk -f "$verifier" -- "$profile/recipes/$recipe/distinfo" \
    "$corrupt") > "$work/corrupt.log" 2>&1; then exit 1; fi
raw=$(shasum -a 1 "$profile/recipes/lang/python314/patches/patch-configure" | awk '{print $1}')
sed "s/^SHA1 (patch-configure) = .*/SHA1 (patch-configure) = $raw/" \
    "$profile/recipes/lang/python314/distinfo" > "$work/raw-distinfo"
if awk -f "$verifier" -- -p "$work/raw-distinfo" \
    "$profile/recipes/lang/python314/patches/patch-configure" > "$work/raw.log" 2>&1; then exit 1; fi
if awk -f "$verifier" -- -p "$profile/recipes/lang/python314/distinfo" \
    "$work/patch-configure" > "$work/missing.log" 2>&1; then exit 1; fi
mkdir "$work/python-pristine" "$work/python-patched"
tar -xf "$distfiles/Python-3.14.8.tar.xz" --strip-components=1 -C "$work/python-pristine"
cp -R "$work/python-pristine/." "$work/python-patched/"
if [ "$scope" = all ]; then
    mkdir "$work/meson-patched"
    tar -xf "$distfiles/meson-1.12.1.tar.gz" --strip-components=1 -C "$work/meson-patched"
fi
for pair in 'lang/python314 python-patched' 'devel/meson meson-patched'; do
    set -- $pair
    [ "$scope" != python-source ] || [ "$1" = lang/python314 ] || continue
    recipe=$profile/recipes/$1 tree=$work/$2
    for delta in "$recipe"/patches/patch-*; do
        patch -f -N -F 0 -p0 -d "$tree" < "$delta"
    done
    first=$(find "$recipe/patches" -type f -name 'patch-*' | LC_ALL=C sort | sed -n '1p')
    if patch -f -N -F 0 -p0 -d "$tree" < "$first" \
        > "$work/repeat-$2.log" 2>&1; then
        echo 'FAIL: repeated patch accepted' >&2; exit 1
    fi
done
! grep -q 'false && test "$cross_compiling"' "$work/python-patched/configure"
grep -q '^PY3LIBRARY=$' "$work/python-patched/Makefile.pre.in"
grep -q -- '-o 0 -o 1 $(COMPILEALL_OPTS)' "$work/python-patched/Makefile.pre.in"
! grep -q -- '-o 0 -o 1 -o 2 $(COMPILEALL_OPTS)' "$work/python-patched/Makefile.pre.in"
for module in test_capi/test_slice test_free_threading/test_context; do
    [ -f "$work/python-pristine/Lib/test/$module.py" ]
    for ext in py pyc pyo; do
        grep -Fqx "lib/python\${PY_VER_SUFFIX}/test/$module.$ext" "$profile/recipes/lang/python314/PLIST"
    done
done
cmp "$work/python-pristine/configure.ac" "$work/python-patched/configure.ac"
cmp "$work/python-pristine/Modules/faulthandler.c" "$work/python-patched/Modules/faulthandler.c"
if [ "$scope" = all ]; then
    cmp "$root/upstream/pkgsrc/devel/meson/PLIST" "$profile/recipes/devel/meson/PLIST"
    # The dropped ELF depfixer patch must leave this upstream implementation exact.
    # The pristine archive copy is small; inspect it without modifying saved sources.
    mkdir "$work/meson-pristine"
    tar -xf "$distfiles/meson-1.12.1.tar.gz" --strip-components=1 -C "$work/meson-pristine"
    cmp "$work/meson-pristine/mesonbuild/scripts/depfixer.py" "$work/meson-patched/mesonbuild/scripts/depfixer.py"
fi
sh "$root/scripts/prepare-pkgsrc.sh" "$work/pkgsrc" common-build-tools > "$work/export.log"
for recipe in lang/python314 devel/meson; do
    [ "$scope" != python-source ] || [ "$recipe" = lang/python314 ] || continue
    diff -r "$profile/recipes/$recipe" "$work/pkgsrc/$recipe"
done
if [ "$scope" = python-source ]; then
    [ ! -e "$work/pkgsrc/lang/python314/patches/patch-Modules_faulthandler.c" ]
    ! grep -q 'patch-Modules_faulthandler.c' "$work/pkgsrc/lang/python314/distinfo"
    echo 'PASS: Python source/checksum/negative cases/export; unchanged Meson/GCC/native contracts not run'
    exit 0
fi
# Existing GCC recipes must remain byte-for-byte identical to the established
# development profile composition. This checks the newly added export mode.
mkdir "$work/gcc-reference"
git -C "$root/upstream/pkgsrc" archive HEAD lang/gcc16 lang/gcc16-libs lang/gcc16-libjit \
    math/mpcomplex devel/gtexinfo lang/tcl-expect | tar -xf - -C "$work/gcc-reference"
for delta in pkgsrc-gcc16.2.patch strict-tests.patch current-prerequisites.patch stable-expect.patch; do
    patch -f -E -F 0 -p1 -d "$work/gcc-reference" < \
        "$root/profiles/development-toolchain/patches/$delta" >> "$work/gcc-export.log"
done
for recipe in lang/gcc16 lang/gcc16-libs lang/gcc16-libjit math/mpcomplex devel/gtexinfo lang/tcl-expect; do
    diff -r "$work/gcc-reference/$recipe" "$work/pkgsrc/$recipe"
done
if sh "$root/scripts/prepare-pkgsrc.sh" "$work/pkgsrc" common-build-tools > "$work/existing.log" 2>&1; then exit 1; fi
if sh "$root/scripts/prepare-pkgsrc.sh" "$work/unknown" invalid > "$work/unknown.log" 2>&1; then exit 1; fi
[ ! -e "$work/unknown" ]
# A private exporter fixture removes one required patch, never the real recipe.
mkdir -p "$work/missing-fixture/scripts" "$work/missing-fixture/upstream" \
    "$work/missing-fixture/profiles/common-build-tools"
cp "$root/scripts/prepare-pkgsrc.sh" "$work/missing-fixture/scripts/"
cp -R "$profile/recipes" "$work/missing-fixture/profiles/common-build-tools/"
ln -s "$root/upstream/pkgsrc" "$work/missing-fixture/upstream/pkgsrc"
git -C "$work/missing-fixture" init -q
pin=$(git -C "$root/upstream/pkgsrc" rev-parse HEAD)
git -C "$work/missing-fixture" update-index --add --cacheinfo "160000,$pin,upstream/pkgsrc"
rm "$work/missing-fixture/profiles/common-build-tools/recipes/lang/python314/patches/patch-configure"
if sh "$work/missing-fixture/scripts/prepare-pkgsrc.sh" "$work/missing-export" \
    common-build-tools > "$work/missing-export.log" 2>&1; then exit 1; fi
grep -q 'Missing required patch: lang/python314/patch-configure' "$work/missing-export.log"
[ ! -e "$work/missing-export" ]
sh "$profile/tests/faulthandler-macro.sh" "$work/python-patched" "$work/python-pristine" "$work/macro"
sh "$profile/tests/meson-selection.sh" "$work/meson-patched" "$work/meson-cli"
if command -v "${BMAKE:-bmake}" >/dev/null 2>&1; then
    sh "$profile/tests/python-selection.sh" "$work/pkgsrc" "$work/python-selection"
else
    echo 'SKIP: actual BSD make selection parsing; bmake unavailable, native gate required'
fi
sh "$profile/tests/llvm-source.sh" "$distfiles" "$work/llvm"
echo 'PASS: source checks; native packaging, ELF fixup and consumer runtime remain pending'
