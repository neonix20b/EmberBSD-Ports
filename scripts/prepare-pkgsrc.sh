#!/bin/sh
# Prepare a pinned pkgsrc tree with the local EmberBSD recipes.
set -eu
umask 022

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
    echo 'Usage: sh scripts/prepare-pkgsrc.sh ABSOLUTE_NEW_DIRECTORY [development-toolchain|common-build-tools|common-graphics|common-media|plasma-mobile]' >&2
    exit 2
}
profile=${2:-}
case "$profile" in
    ''|development-toolchain|common-build-tools|common-graphics|common-media|plasma-mobile) ;;
    *) echo 'Unknown profile.' >&2; exit 2 ;;
esac
destination=$1
case "$destination" in
    /*) ;;
    *) echo 'Destination must be absolute.' >&2; exit 2 ;;
esac
case "$destination" in
    *[!a-zA-Z0-9_./-]*) echo 'pkgsrc requires a path without whitespace or shell metacharacters.' >&2; exit 2 ;;
esac
[ ! -e "$destination" ] && [ ! -L "$destination" ] || { echo 'Destination already exists.' >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
expected=$(git -C "$root" ls-files --stage -- upstream/pkgsrc | awk '$1 == "160000" { print $2 }')
actual=$(git -C "$root/upstream/pkgsrc" rev-parse HEAD)
[ -n "$expected" ] && [ "$actual" = "$expected" ] || {
    echo 'Initialize the pinned submodule with git submodule update --init upstream/pkgsrc.' >&2
    exit 2
}
if [ "$profile" = common-build-tools ] || [ "$profile" = common-graphics ] || [ "$profile" = common-media ] || [ "$profile" = plasma-mobile ]; then
    for recipe in lang/python314 devel/meson lang/llvm lang/clang devel/lld devel/py-llvm-lit; do
        source=$root/profiles/common-build-tools/recipes/$recipe
        [ -f "$source/Makefile" ] && [ -f "$source/PLIST" ] && \
            [ -f "$source/distinfo" ] || {
            echo "Incomplete common-tools recipe: $recipe" >&2; exit 2;
        }
        required=$(awk '/^SHA1 \(patch-/ { gsub(/[()]/, "", $2); print $2 }' "$source/distinfo")
        case "$recipe" in
            devel/lld|devel/py-llvm-lit) ;;
            *) [ -n "$required" ] || { echo "No patch checksums: $recipe" >&2; exit 2; } ;;
        esac
        for name in $required; do
            [ -f "$source/patches/$name" ] || {
                echo "Missing required patch: $recipe/$name" >&2; exit 2;
            }
        done
    done
fi
if [ "$profile" = common-media ] || [ "$profile" = plasma-mobile ]; then
    media=$root/profiles/common-media
    sh "$media/validate.sh"
fi
if [ "$profile" = plasma-mobile ]; then
    toolkit=$root/probes/plasma-mobile/toolkit
    awk -F '\t' '
        /^#/ || /^$/ { next }
        NF != 4 || $1 !~ /^[a-z0-9][a-z0-9-]*\/[a-z0-9][a-z0-9+-]*$/ ||
            $2 !~ /^[a-zA-Z0-9][a-zA-Z0-9._+-]*\.tar\.xz$/ ||
            length($3) != 64 || $3 !~ /^[0-9a-f]+$/ || seen[$1]++ { exit 1 }
        END { if (NR == 0) exit 1 }
    ' "$toolkit/sources.tsv" || { echo 'Invalid toolkit source manifest.' >&2; exit 2; }
    recipes=$(find "$toolkit/recipes" -name Makefile -type f | wc -l | tr -d ' ')
    entries=$(awk '!/^#/ && NF { n++ } END { print n+0 }' "$toolkit/sources.tsv")
    [ "$entries" -gt 0 ] && [ "$recipes" = "$entries" ] || {
        echo 'Incomplete toolkit source manifest.' >&2; exit 2;
    }
    while IFS="$(printf '\t')" read -r recipe dist_archive sha url; do
        case "$recipe" in ''|'#'*) continue ;; esac
        source=$toolkit/recipes/$recipe
        for name in Makefile PLIST distinfo; do
            [ -f "$source/$name" ] || {
                echo "Incomplete toolkit recipe: $recipe/$name" >&2; exit 2;
            }
        done
        for name in $(awk '/^SHA1 \(patch-/ { gsub(/[()]/, "", $2); print $2 }' "$source/distinfo"); do
            [ -f "$source/patches/$name" ] || {
                echo "Missing required patch: $recipe/$name" >&2; exit 2;
            }
        done
    done < "$toolkit/sources.tsv"
fi
if [ "$profile" = common-graphics ] || [ "$profile" = common-media ] || [ "$profile" = plasma-mobile ]; then
    graphics=$root/profiles/common-graphics
    awk -F '\t' '
        /^#/ || /^$/ { next }
        NF != 4 || ($1 != "graphics/MesaLib" && $1 != "x11/libdrm") ||
            $2 !~ /^[a-zA-Z0-9][a-zA-Z0-9._+-]*\.tar\.xz$/ ||
            length($3) != 64 || $3 !~ /^[0-9a-f]+$/ ||
            $4 !~ /^https:\/\// || seen[$1]++ { bad=1 }
        END { if (bad || !seen["graphics/MesaLib"] || !seen["x11/libdrm"]) exit 1 }
    ' "$graphics/sources.tsv" || { echo 'Invalid common graphics manifest.' >&2; exit 2; }
    while IFS="$(printf '\t')" read -r recipe archive sha url; do
        case "$recipe" in
            ''|'#'*) continue ;;
            graphics/MesaLib) pin='mesa-26.2.4.tar.xz:bce5f7fbebb934373b86c999a064d52fb5065878dc57f287f95346648ec832e9:https://archive.mesa3d.org/mesa-26.2.4.tar.xz' ;;
            x11/libdrm) pin='libdrm-2.4.134.tar.xz:ac5e74d157830eb8bee44c6a6bf3ad49774ef0dd2a72bdad74a8f20308b52a95:https://dri.freedesktop.org/libdrm/libdrm-2.4.134.tar.xz' ;;
        esac
        [ "$archive:$sha:$url" = "$pin" ] || { echo "Incorrect common graphics source pin: $recipe" >&2; exit 2; }
    done < "$graphics/sources.tsv"
    for recipe in graphics/MesaLib x11/libdrm; do
        source=$graphics/recipes/$recipe
        for name in Makefile DESCR PLIST distinfo buildlink3.mk builtin.mk; do
            [ -f "$source/$name" ] || { echo "Incomplete graphics recipe: $recipe/$name" >&2; exit 2; }
        done
        case "$recipe" in
            graphics/MesaLib)
                approved='patch-bin_symbols-check.py patch-dso-lifetime patch-meson-python-selection patch-src_util_half__float.c' ;;
            x11/libdrm)
                approved='patch-ac patch-amdgpu_amdgpu__cs.c patch-include_drm_drm.h patch-libsync.h patch-symbols-check.py patch-tests_nouveau_threaded.c patch-xf86drm.c patch-xf86drmMode.c patch-zz-native-identity patch-zzz-native-warnings' ;;
        esac
        for name in $approved; do
            grep -q "^SHA1 ($name) = " "$source/distinfo" && [ -f "$source/patches/$name" ] || {
                echo "Missing required graphics patch: $recipe/$name" >&2; exit 2;
            }
        done
        required=$(awk '/^SHA1 \(patch-/ { gsub(/[()]/, "", $2); print $2 }' "$source/distinfo")
        [ -n "$required" ] || { echo "No graphics patch checksums: $recipe" >&2; exit 2; }
        actual=$(find "$source/patches" -type f -name 'patch-*' | wc -l | tr -d ' ')
        count=$(printf '%s\n' "$required" | wc -l | tr -d ' ')
        [ "$actual" = "$count" ] || { echo "Graphics patch inventory differs: $recipe" >&2; exit 2; }
        for name in $required; do
            [ -f "$source/patches/$name" ] || { echo "Missing required patch: $recipe/$name" >&2; exit 2; }
            recorded=$(awk -v name="($name)" '$1 == "SHA1" && $2 == name { print $4 }' "$source/distinfo")
            computed=$(sed '/[$]NetBSD.*/d' "$source/patches/$name" | shasum -a 1 | awk '{ print $1 }')
            [ "$recorded" = "$computed" ] || { echo "Graphics patch checksum differs: $recipe/$name" >&2; exit 2; }
        done
    done
    for name in features.mk options.mk version.mk; do
        [ -f "$graphics/recipes/graphics/MesaLib/$name" ] || { echo "Incomplete Mesa recipe: $name" >&2; exit 2; }
    done
    [ -f "$graphics/mk.conf" ] || { echo 'Missing common graphics configuration.' >&2; exit 2; }
fi
export_archive=$(mktemp "${TMPDIR:-/tmp}/ember-pkgsrc.XXXXXXXX")
trap 'rm -f "$export_archive"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
git -C "$root/upstream/pkgsrc" archive --format=tar --output="$export_archive" "$expected"
mkdir "$destination"
tar -xf "$export_archive" -C "$destination"
for category in "$root"/pkgsrc/*; do
    [ -d "$category" ] || continue
    name=${category##*/}
    [ ! -e "$destination/$name" ] && [ ! -L "$destination/$name" ] || {
        echo "Upstream already has $name; review the overlay." >&2
        exit 2
    }
    cp -R "$category" "$destination/$name"
done
if [ "$profile" = development-toolchain ] || [ "$profile" = common-build-tools ] || \
    [ "$profile" = common-graphics ] || [ "$profile" = common-media ] || [ "$profile" = plasma-mobile ]; then
    for delta in pkgsrc-gcc16.2.patch strict-tests.patch current-prerequisites.patch stable-expect.patch gcc-tsvc-netbsd.patch gcc-modules-fallocate.patch gcc-package-requires.patch; do
        patch -f -E -d "$destination" -p1 -F 0 < \
            "$root/profiles/development-toolchain/patches/$delta"
    done
    cp "$root/profiles/development-toolchain/mk.conf" \
        "$destination/EMBERBSD-DEVELOPMENT-MK.CONF"
fi
if [ "$profile" = common-build-tools ] || [ "$profile" = common-graphics ] || [ "$profile" = common-media ] || [ "$profile" = plasma-mobile ]; then
    for recipe in lang/python314 devel/meson lang/llvm lang/clang devel/lld devel/py-llvm-lit; do
        source=$root/profiles/common-build-tools/recipes/$recipe
        # Replace only recipe paths inside this newly created export.
        rm -rf "$destination/$recipe"
        cp -R "$source" "$destination/$recipe"
    done
    patch -f -N -d "$destination" -p1 -F 0 < \
        "$root/profiles/common-build-tools/patches/current-python-selection.patch"
    cp "$root/profiles/common-build-tools/mk.conf" \
        "$destination/EMBERBSD-COMMON-TOOLS-MK.CONF"
fi
if [ "$profile" = common-graphics ] || [ "$profile" = common-media ] || [ "$profile" = plasma-mobile ]; then
    for recipe in graphics/MesaLib x11/libdrm; do
        rm -rf "$destination/$recipe"
        cp -R "$graphics/recipes/$recipe" "$destination/$recipe"
    done
    cp "$graphics/mk.conf" "$destination/EMBERBSD-COMMON-GRAPHICS-MK.CONF"
    cp "$graphics/sources.tsv" "$destination/EMBERBSD-COMMON-GRAPHICS-SOURCES"
fi
if [ "$profile" = common-media ] || [ "$profile" = plasma-mobile ]; then
    # Replace the existing 9.0.1 recipe in this newly created export.
    rm -rf "$destination/multimedia/ffmpeg9"
    cp -R "$media/recipes/multimedia/ffmpeg9" "$destination/multimedia/ffmpeg9"
    cp "$media/mk.conf" "$destination/EMBERBSD-COMMON-MEDIA-MK.CONF"
    cp "$media/sources.tsv" "$destination/EMBERBSD-COMMON-MEDIA-SOURCES"
fi
if [ "$profile" = plasma-mobile ]; then
    while IFS="$(printf '\t')" read -r recipe dist_archive sha url; do
        case "$recipe" in ''|'#'*) continue ;; esac
        rm -rf "$destination/$recipe"
        cp -R "$toolkit/recipes/$recipe" "$destination/$recipe"
    done < "$toolkit/sources.tsv"
    cp -R "$toolkit/shared/." "$destination/"
    cp "$toolkit/mk.conf" "$destination/EMBERBSD-PLASMA-TOOLKIT-MK.CONF"
fi
printf '%s\n' "$expected" > "$destination/EMBERBSD-PKGSRC-REVISION"
printf 'Prepared %s with pkgsrc %s\n' "$destination" "$expected"
