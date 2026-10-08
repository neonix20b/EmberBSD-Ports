#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted canonical export and failure checks.
set -eu
[ "$#" -eq 1 ] || { echo "Usage: $0 NEW_WORK" >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
mkdir "$1"
work=$(CDPATH= cd -- "$1" && pwd)
# Disposable source view shares read-only Git metadata; it never stages/commits.
mkdir -p "$work/source/scripts" "$work/source/profiles" "$work/tmp" "$work/bin"
cp "$root/scripts/prepare-pkgsrc.sh" "$work/source/scripts/"
cp -R "$root/profiles/common-graphics" "$work/source/profiles/"
ln -s "$root/.git" "$work/source/.git"
ln -s "$root/upstream" "$work/source/upstream"
ln -s "$root/profiles/common-media" "$work/source/profiles/common-media"
ln -s "$root/profiles/common-build-tools" "$work/source/profiles/common-build-tools"
ln -s "$root/profiles/development-toolchain" "$work/source/profiles/development-toolchain"
ln -s "$root/probes" "$work/source/probes"
cp -R "$root/pkgsrc" "$work/source/pkgsrc"
script=$work/source/scripts/prepare-pkgsrc.sh
profile=$work/source/profiles/common-graphics
negative() {
    if sh "$script" "$work/rejected" common-graphics > "$work/$1.log" 2>&1; then exit 1; fi
    [ ! -e "$work/rejected" ]
}
pkg=$profile/recipes/graphics/MesaLib
mv "$pkg/Makefile" "$pkg/Makefile.saved"
negative missing-recipe
mv "$pkg/Makefile.saved" "$pkg/Makefile"
patch=$pkg/patches/patch-meson-python-selection
mv "$patch" "$work/saved-patch"
negative missing-patch
cp "$work/saved-patch" "$patch"
printf '\nchanged\n' >> "$patch"
negative altered-patch
cp "$work/saved-patch" "$patch"
# Omitting both a patch and its checksum must also fail before destination creation.
cp "$pkg/distinfo" "$work/saved-distinfo"
mv "$pkg/patches/patch-dso-lifetime" "$work/saved-lifetime"
sed '/SHA1 (patch-dso-lifetime)/d' "$work/saved-distinfo" > "$pkg/distinfo"
negative omitted-accepted-patch
mv "$work/saved-lifetime" "$pkg/patches/patch-dso-lifetime"
cp "$work/saved-distinfo" "$pkg/distinfo"
wayland=$profile/recipes/devel/wayland
cp "$wayland/distinfo" "$work/wayland-distinfo"
for name in patch-tests_client-test.c patch-tests_test-helpers.c; do
    mv "$wayland/patches/$name" "$work/$name"
    sed "/SHA1 ($name)/d" "$work/wayland-distinfo" > "$wayland/distinfo"
    negative "omitted-$name"
    mv "$work/$name" "$wayland/patches/$name"
    cp "$work/wayland-distinfo" "$wayland/distinfo"
done
consumer=$profile/recipes/devel/wayland-protocols/cross-scanner.mk
mv "$consumer" "$work/scanner-consumer.mk"
negative missing-scanner-consumer
mv "$work/scanner-consumer.mk" "$consumer"
cp "$profile/sources.tsv" "$work/saved-manifest"
sed 's/bce5f7fb/00000000/' "$work/saved-manifest" > "$profile/sources.tsv"
negative altered-manifest
cp "$work/saved-manifest" "$profile/sources.tsv"
for dependency in x11/xorgproto devel/libudev-bsd; do
    # These unpatched upstream recipes still need their exact source pins.
    awk -F '\t' -v dep="$dependency" 'BEGIN { OFS="\t" }
        $1 == dep { $3="0000000000000000000000000000000000000000000000000000000000000000" }
        { print }' "$work/saved-manifest" > "$profile/sources.tsv"
    negative "altered-${dependency##*/}-pin"
    cp "$work/saved-manifest" "$profile/sources.tsv"
    mv "$profile/recipes/$dependency/Makefile" "$work/dependency-Makefile"
    negative "missing-${dependency##*/}-recipe"
    mv "$work/dependency-Makefile" "$profile/recipes/$dependency/Makefile"
done
if sh "$script" "$work/unknown" unknown > "$work/unknown.log" 2>&1; then exit 1; fi
[ ! -e "$work/unknown" ]
# Failure after archive creation must preserve its status and clean the tempfile.
REAL_CP=$(command -v cp); export REAL_CP
cat > "$work/bin/cp" <<'SH'
#!/bin/sh
for arg do
    if [ "$arg" = "${GRAPHICS_FAIL_SOURCE:-}" ]; then exit 42; fi
done
exec "$REAL_CP" "$@"
SH
chmod +x "$work/bin/cp"
status=0
PATH="$work/bin:$PATH" TMPDIR="$work/tmp" GRAPHICS_FAIL_SOURCE="$pkg" \
    sh "$script" "$work/failed-export" common-graphics > "$work/failed-export.log" 2>&1 || status=$?
[ "$status" -eq 42 ]
[ -z "$(find "$work/tmp" -name 'ember-pkgsrc.*')" ]
# Only completed disposable source exports are removed; logs remain.
rm -rf "$work/failed-export"
for mode in default development-toolchain common-build-tools common-graphics common-media plasma-mobile; do
    tree=$work/export
    if [ "$mode" = default ]; then sh "$script" "$tree" > "$work/$mode.log" 2>&1
    else sh "$script" "$tree" "$mode" > "$work/$mode.log" 2>&1; fi
    case "$mode" in
        common-graphics|common-media|plasma-mobile)
            for recipe in graphics/MesaLib x11/libdrm devel/wayland devel/wayland-protocols x11/xorgproto devel/libudev-bsd; do diff -qr "$profile/recipes/$recipe" "$tree/$recipe"; done
            cmp "$profile/mk.conf" "$tree/EMBERBSD-COMMON-GRAPHICS-MK.CONF"
            cmp "$profile/sources.tsv" "$tree/EMBERBSD-COMMON-GRAPHICS-SOURCES" ;;
        *)
            for recipe in graphics/MesaLib x11/libdrm devel/wayland devel/wayland-protocols x11/xorgproto devel/libudev-bsd; do diff -qr "$root/upstream/pkgsrc/$recipe" "$tree/$recipe"; done
            [ ! -e "$tree/EMBERBSD-COMMON-GRAPHICS-MK.CONF" ] ;;
    esac
    case "$mode" in common-build-tools|common-graphics|common-media|plasma-mobile)
        for recipe in lang/python314 devel/meson lang/llvm lang/clang devel/lld devel/py-llvm-lit devel/binutils devel/py-mako textproc/py-markupsafe textproc/py-yaml; do diff -qr "$root/profiles/common-build-tools/recipes/$recipe" "$tree/$recipe"; done
        cmp "$root/profiles/common-build-tools/mk.conf" "$tree/EMBERBSD-COMMON-TOOLS-MK.CONF" ;;
    esac
    case "$mode" in development-toolchain|common-build-tools|common-graphics|common-media|plasma-mobile)
        cmp "$root/profiles/development-toolchain/mk.conf" "$tree/EMBERBSD-DEVELOPMENT-MK.CONF" ;;
    esac
    case "$mode" in
        common-media|plasma-mobile)
            diff -qr "$root/profiles/common-media/recipes/multimedia/ffmpeg9" "$tree/multimedia/ffmpeg9"
            cmp "$root/profiles/common-media/mk.conf" "$tree/EMBERBSD-COMMON-MEDIA-MK.CONF" ;;
        *) diff -qr "$root/upstream/pkgsrc/multimedia/ffmpeg9" "$tree/multimedia/ffmpeg9"; [ ! -e "$tree/EMBERBSD-COMMON-MEDIA-MK.CONF" ] ;;
    esac
    if [ "$mode" = plasma-mobile ]; then

        while IFS="$(printf '\t')" read -r recipe archive sha url; do
            case "$recipe" in ''|'#'*) continue ;; esac
            diff -qr "$root/probes/plasma-mobile/toolkit/recipes/$recipe" "$tree/$recipe"
        done < "$root/probes/plasma-mobile/toolkit/sources.tsv"
        cmp "$root/probes/plasma-mobile/toolkit/mk.conf" "$tree/EMBERBSD-PLASMA-TOOLKIT-MK.CONF"
    fi
    if sh "$script" "$tree" > "$work/existing-$mode.log" 2>&1; then exit 1; fi
    printf '%s: exact composition passed\n' "$mode" >> "$work/composition.txt"
    rm -rf "$tree"
done
# The old namespace collision refusal remains active even in the new profile.
mkdir "$work/source/pkgsrc/graphics"
if sh "$script" "$work/collision" common-graphics > "$work/collision.log" 2>&1; then exit 1; fi
grep 'Upstream already has graphics' "$work/collision.log"
rm -rf "$work/collision"
echo 'PASS: canonical composition, preserved sibling modes and the composed media profile, preflight failures, namespace collision and tempfile cleanup'
