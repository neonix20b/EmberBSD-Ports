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
    for recipe in lang/python314 devel/meson lang/llvm lang/clang devel/lld devel/py-llvm-lit devel/binutils devel/py-mako textproc/py-markupsafe textproc/py-yaml; do
        source=$root/profiles/common-build-tools/recipes/$recipe
        [ -f "$source/Makefile" ] && [ -f "$source/PLIST" ] && \
            [ -f "$source/distinfo" ] || {
            echo "Incomplete common-tools recipe: $recipe" >&2; exit 2;
        }
        required=$(awk '/^SHA1 \(patch-/ { gsub(/[()]/, "", $2); print $2 }' "$source/distinfo")
        case "$recipe" in
            devel/lld|devel/py-llvm-lit|devel/py-mako|textproc/py-markupsafe|textproc/py-yaml) ;;
            *) [ -n "$required" ] || { echo "No patch checksums: $recipe" >&2; exit 2; } ;;
        esac
        for name in $required; do
            [ -f "$source/patches/$name" ] || {
                echo "Missing required patch: $recipe/$name" >&2; exit 2;
            }
        done
    done
    for delta in current-libtool.patch pkgsrc-cross-packages.patch; do
        [ -s "$root/profiles/common-build-tools/patches/$delta" ] || {
            echo "Missing common-tools infrastructure patch: $delta" >&2; exit 2;
        }
    done
    [ -s "$root/profiles/common-build-tools/cross/mk.conf" ] || exit 2
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
        NF != 4 || ($1 != "graphics/MesaLib" && $1 != "x11/libdrm" &&
            $1 != "devel/wayland" && $1 != "devel/wayland-protocols" &&
            $1 != "x11/xorgproto" && $1 != "devel/libudev-bsd") ||
            $2 !~ /^[a-zA-Z0-9][a-zA-Z0-9._+-]*\.tar\.(xz|gz)$/ ||
            length($3) != 64 || $3 !~ /^[0-9a-f]+$/ ||
            $4 !~ /^https:\/\// || seen[$1]++ { bad=1 }
        END { if (bad || !seen["graphics/MesaLib"] || !seen["x11/libdrm"] ||
            !seen["devel/wayland"] || !seen["devel/wayland-protocols"] ||
            !seen["x11/xorgproto"] || !seen["devel/libudev-bsd"]) exit 1 }
    ' "$graphics/sources.tsv" || { echo 'Invalid common graphics manifest.' >&2; exit 2; }
    while IFS="$(printf '\t')" read -r recipe archive sha url; do
        case "$recipe" in
            ''|'#'*) continue ;;
            graphics/MesaLib) pin='mesa-26.2.4.tar.xz:bce5f7fbebb934373b86c999a064d52fb5065878dc57f287f95346648ec832e9:https://archive.mesa3d.org/mesa-26.2.4.tar.xz' ;;
            x11/libdrm) pin='libdrm-2.4.134.tar.xz:ac5e74d157830eb8bee44c6a6bf3ad49774ef0dd2a72bdad74a8f20308b52a95:https://dri.freedesktop.org/libdrm/libdrm-2.4.134.tar.xz' ;;
            devel/wayland) pin='wayland-1.26.0.tar.xz:64176eaa46e4969903e286f8e5ef8331affc17fdf03ac9b58381d2b23162b7a3:https://gitlab.freedesktop.org/wayland/wayland/-/releases/1.26.0/downloads/wayland-1.26.0.tar.xz' ;;
            devel/wayland-protocols) pin='wayland-protocols-1.49.tar.xz:ec4c8f74942d6dff7ace8b4ce4764f0ef9ff618a935d974ea77edee2ad240b14:https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/1.49/downloads/wayland-protocols-1.49.tar.xz' ;;
            x11/xorgproto) pin='xorgproto-2026.1.tar.xz:f9bfe4a9ed8c8ab9d2a3b0d49797f046052dadd06b7a8b45dbffaffb137e8290:https://xorg.freedesktop.org/archive/individual/proto/xorgproto-2026.1.tar.xz' ;;
            devel/libudev-bsd) pin='libudev-bsd-0.7.0.1.tar.gz:c4a8c30781438a76720f77876ca362b7a5ecd41d15cd603d52097c2cb10425f0:https://github.com/kikadf/libudev-bsd/archive/v0.7.0.1.tar.gz' ;;
        esac
        [ "$archive:$sha:$url" = "$pin" ] || { echo "Incorrect common graphics source pin: $recipe" >&2; exit 2; }
    done < "$graphics/sources.tsv"
    for recipe in graphics/MesaLib x11/libdrm devel/wayland devel/wayland-protocols x11/xorgproto devel/libudev-bsd; do
        source=$graphics/recipes/$recipe
        for name in Makefile DESCR PLIST distinfo buildlink3.mk; do
            [ -f "$source/$name" ] || { echo "Incomplete graphics recipe: $recipe/$name" >&2; exit 2; }
        done
        case "$recipe" in
            graphics/MesaLib)
                approved='patch-bin_symbols-check.py patch-dso-lifetime patch-include_c99__alloca.h patch-meson-python-selection patch-meson-xcb-pkgconfig patch-src_gallium_auxiliary_vl_vl__csc.c patch-src_util_half__float.c' ;;
            x11/libdrm)
                approved='patch-ac patch-amdgpu_amdgpu__cs.c patch-include_drm_drm.h patch-libsync.h patch-symbols-check.py patch-tests_nouveau_threaded.c patch-xf86drm.c patch-xf86drmMode.c patch-zz-native-identity patch-zzz-native-warnings' ;;
            devel/wayland)
                approved='patch-meson.build patch-meson__options.txt patch-scanner.c patch-src_meson.build patch-src_wayland-os.c patch-tests_client-test.c patch-tests_test-helpers.c' ;;
            devel/wayland-protocols)
                approved='patch-stable_xdg-shell_xdg-shell.xml patch-unstable_xdg-output_xdg-output-unstable-v1.xml' ;;
            x11/xorgproto|devel/libudev-bsd) approved='' ;;
        esac
        case "$recipe" in
            graphics/MesaLib|x11/libdrm)
                [ -f "$source/builtin.mk" ] || { echo "Missing builtin guard: $recipe" >&2; exit 2; } ;;
            devel/wayland)
                [ -f "$source/cross-scanner.mk" ] && [ -f "$source/platform.mk" ] || exit 2 ;;
            devel/wayland-protocols)
                [ -f "$source/cross-scanner.mk" ] || { echo 'Missing protocols host scanner integration' >&2; exit 2; } ;;
        esac
        for name in $approved; do
            grep -q "^SHA1 ($name) = " "$source/distinfo" && [ -f "$source/patches/$name" ] || {
                echo "Missing required graphics patch: $recipe/$name" >&2; exit 2;
            }
        done
        required=$(awk '/^SHA1 \(patch-/ { gsub(/[()]/, "", $2); print $2 }' "$source/distinfo")
        case "$recipe" in
            x11/xorgproto|devel/libudev-bsd) ;;
            *) [ -n "$required" ] || { echo "No graphics patch checksums: $recipe" >&2; exit 2; } ;;
        esac
        actual=0
        if [ -d "$source/patches" ]; then
            actual=$(find "$source/patches" -type f -name 'patch-*' | wc -l | tr -d ' ')
        fi
        count=$(printf '%s\n' "$required" | awk 'NF { n++ } END { print n+0 }')
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
    # One current debugger recipe; dereference the shared Ports patch links.
    rm -rf "$destination/devel/gdb"
    cp -RL "$root/profiles/development-toolchain/recipes/devel/gdb" "$destination/devel/gdb"
    cp "$root/profiles/development-toolchain/mk.conf" \
        "$destination/EMBERBSD-DEVELOPMENT-MK.CONF"
fi
if [ "$profile" = common-build-tools ] || [ "$profile" = common-graphics ] || [ "$profile" = common-media ] || [ "$profile" = plasma-mobile ]; then
    for recipe in lang/python314 devel/meson lang/llvm lang/clang devel/lld devel/py-llvm-lit devel/binutils devel/py-mako textproc/py-markupsafe textproc/py-yaml; do
        source=$root/profiles/common-build-tools/recipes/$recipe
        # Replace only recipe paths inside this newly created export.
        rm -rf "$destination/$recipe"
        cp -R "$source" "$destination/$recipe"
    done
    patch -f -N -d "$destination" -p1 -F 0 < \
        "$root/profiles/common-build-tools/patches/current-python-selection.patch"
    for delta in current-libtool.patch pkgsrc-cross-packages.patch; do
        patch -f -N -d "$destination" -p1 -F 0 < \
            "$root/profiles/common-build-tools/patches/$delta"
    done
    cp "$root/profiles/common-build-tools/mk.conf" \
        "$destination/EMBERBSD-COMMON-TOOLS-MK.CONF"
    cp "$root/profiles/common-build-tools/cross/mk.conf" \
        "$destination/EMBERBSD-CROSS-MK.CONF"
fi
if [ "$profile" = common-graphics ] || [ "$profile" = common-media ] || [ "$profile" = plasma-mobile ]; then
    for recipe in graphics/MesaLib x11/libdrm devel/wayland devel/wayland-protocols x11/xorgproto devel/libudev-bsd; do
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
