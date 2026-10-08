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
            $1 != "x11/xorgproto" && $1 != "devel/libudev-bsd" &&
            $1 != "wayland/wlroots" && $1 != "x11/xkeyboard-config" && $1 != "devel/input-headers" && $1 != "x11/libxkbcommon" && $1 != "sysutils/hwdata" && $1 != "sysutils/seatd" && $1 != "x11/libdisplay-info" && $1 != "graphics/libliftoff" && $1 != "devel/libopeninput" &&
            $1 != "devel/glib2" &&
            $1 != "devel/pcre2" &&
            $1 != "graphics/cairo" &&
            $1 != "fonts/harfbuzz" &&
            $1 != "converters/fribidi" &&
            $1 != "graphics/png" &&
            $1 != "graphics/freetype2" &&
            $1 != "archivers/lzo") ||
            $2 !~ /^[a-zA-Z0-9][a-zA-Z0-9._+-]*\.tar\.(xz|gz)$/ ||
            length($3) != 64 || $3 !~ /^[0-9a-f]+$/ ||
            $4 !~ /^https:\/\// || seen[$1]++ { bad=1 }
        END { if (bad || !seen["graphics/MesaLib"] || !seen["x11/libdrm"] ||
            !seen["devel/wayland"] || !seen["devel/wayland-protocols"] ||
            !seen["x11/xorgproto"] || !seen["devel/libudev-bsd"] ||
            !seen["wayland/wlroots"] || !seen["x11/xkeyboard-config"] || !seen["devel/input-headers"] || !seen["x11/libxkbcommon"] || !seen["sysutils/hwdata"] || !seen["sysutils/seatd"] || !seen["x11/libdisplay-info"] || !seen["graphics/libliftoff"] || !seen["devel/libopeninput"] ||
            !seen["devel/glib2"] ||
            !seen["devel/pcre2"] ||
            !seen["graphics/cairo"] ||
            !seen["fonts/harfbuzz"] ||
            !seen["converters/fribidi"] ||
            !seen["graphics/png"] ||
            !seen["graphics/freetype2"] ||
            !seen["archivers/lzo"]) exit 1 }
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
            wayland/wlroots) pin='wlroots-0.20.2.tar.gz:972c7ac44b17828f4702bfae7cd8347346a3fb5b2c1076cfa2c3fcedac5ec343:https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/0.20.2/wlroots-0.20.2.tar.gz' ;;
            x11/xkeyboard-config) pin='xkeyboard-config-2.48.tar.xz:b77041324f0109f77161ee43743fe04baa485866af8460d31e476ad3f7648fd5:https://xorg.freedesktop.org/archive/individual/data/xkeyboard-config/xkeyboard-config-2.48.tar.xz' ;;
            devel/input-headers) pin='libopeninput-1.31.3-10995219206280da0f1a3ba124abe4c8ef89e021.tar.gz:fbba09ed60a9a411b9ae7ee5c92daf069a3b4926ad052ac8cbcfb7c3ff82abbf:https://github.com/sizeofvoid/libopeninput/archive/10995219206280da0f1a3ba124abe4c8ef89e021.tar.gz' ;;
            sysutils/hwdata) pin='hwdata-0.412.tar.gz:f0c64cd7e31d70a5fb3a52e53ab50a61e74c0421a6381eaa45114eec3bde5fe7:https://github.com/vcrhonek/hwdata/archive/v0.412.tar.gz' ;;
            sysutils/seatd) pin='seatd-0.9.3.tar.gz:302564d54d8e28191fadfd734f2675ecb0c9e0615a58011b89ef15dfa4dbaa96:https://github.com/kennylevinsen/seatd/archive/refs/tags/0.9.3.tar.gz' ;;
            x11/libdisplay-info) pin='libdisplay-info-0.4.0.tar.xz:43b180baa143e2035654759d84e2b2f5ee77d5fe817c423838c7fe59c0d68459:https://gitlab.freedesktop.org/emersion/libdisplay-info/-/releases/0.4.0/downloads/libdisplay-info-0.4.0.tar.xz' ;;
            graphics/libliftoff) pin='libliftoff-0.5.0.tar.gz:3309218c3137a70faada653690802b514e4e46d9b38e7d9d5948ffcc4831f3b1:https://gitlab.freedesktop.org/emersion/libliftoff/-/archive/v0.5.0/libliftoff-v0.5.0.tar.gz' ;;
            devel/libopeninput) pin='libopeninput-1.31.3-10995219206280da0f1a3ba124abe4c8ef89e021.tar.gz:fbba09ed60a9a411b9ae7ee5c92daf069a3b4926ad052ac8cbcfb7c3ff82abbf:https://github.com/sizeofvoid/libopeninput/archive/10995219206280da0f1a3ba124abe4c8ef89e021.tar.gz' ;;
            x11/libxkbcommon) pin='xkbcommon-1.13.2.tar.gz:acc4d5f7c3cbba5f9f8d08d8bdbeede84ecede46792f47929aa9321873385528:https://github.com/xkbcommon/libxkbcommon/archive/xkbcommon-1.13.2.tar.gz' ;;
            devel/glib2) pin='glib-2.90.1.tar.xz:93c941aa17d5eb1d53fe838365f29a8b4e539c222a256d974ec8f30fc413e396:https://download.gnome.org/sources/glib/2.90/glib-2.90.1.tar.xz' ;;
            devel/pcre2) pin='pcre2-10.49.tar.gz:929f0b20e62879252a15886b06c89f1edef61a363cbd5826fb041080a5e557ae:https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.49/pcre2-10.49.tar.gz' ;;
            graphics/cairo) pin='cairo-1.18.6.tar.xz:1c767308174337a74694da0f3ec069c271452163a1ef4540964c50c301f157d4:https://cairographics.org/releases/cairo-1.18.6.tar.xz' ;;
            fonts/harfbuzz) pin='harfbuzz-14.6.0.tar.xz:d07a007327277708a2a73ae437887cdbaf282937f6d03ca5467723e9099af586:https://github.com/harfbuzz/harfbuzz/releases/download/14.6.0/harfbuzz-14.6.0.tar.xz' ;;
            converters/fribidi) pin='fribidi-1.0.17.tar.xz:6949dcde27d41cebad1fd741fcafc36d55a1020d2d872d4a6eb3914caabbada2:https://github.com/fribidi/fribidi/releases/download/v1.0.17/fribidi-1.0.17.tar.xz' ;;
            graphics/png) pin='libpng-1.6.59.tar.xz:d80dd2a38a37f803cb9b6ac7b14bd6e74ddc3b654780a8380bdf93523fdb4389:https://downloads.sourceforge.net/project/libpng/libpng16/1.6.59/libpng-1.6.59.tar.xz' ;;
            graphics/freetype2) pin='freetype-2.14.3.tar.xz:36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f:https://download.savannah.gnu.org/releases/freetype/freetype-2.14.3.tar.xz' ;;
            archivers/lzo) pin='lzo-2.10.tar.gz:c0f892943208266f9b6543b3ae308fab6284c5c90e627931446fb49b4221a072:https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz' ;;
        esac
        [ "$archive:$sha:$url" = "$pin" ] || { echo "Incorrect common graphics source pin: $recipe" >&2; exit 2; }
    done < "$graphics/sources.tsv"
    for recipe in graphics/MesaLib x11/libdrm devel/wayland devel/wayland-protocols x11/xorgproto devel/libudev-bsd wayland/wlroots x11/xkeyboard-config devel/input-headers x11/libxkbcommon sysutils/hwdata sysutils/seatd x11/libdisplay-info graphics/libliftoff devel/libopeninput devel/glib2 devel/pcre2 graphics/cairo fonts/harfbuzz converters/fribidi graphics/png graphics/freetype2 archivers/lzo devel/glib2-tools devel/glib2-introspection devel/gdbus-codegen; do
        source=$graphics/recipes/$recipe
        recipe_files='Makefile DESCR PLIST distinfo buildlink3.mk'
        case "$recipe" in
            devel/glib2-tools|devel/glib2-introspection) recipe_files='Makefile DESCR PLIST' ;;
            devel/gdbus-codegen) recipe_files='Makefile DESCR PLIST distinfo' ;;
        esac
        for name in $recipe_files; do
            [ -f "$source/$name" ] || { echo "Incomplete graphics recipe: $recipe/$name" >&2; exit 2; }
        done
        case "$recipe" in
            devel/glib2) approved='patch-gio_gcredentialsprivate.h patch-gio_gdbus-2.0_codegen_meson.build patch-gio_glib-compile-schemas.c patch-gio_gresource-tool.c patch-gio_gunixcredentialsmessage.c patch-gio_gunixmounts.c patch-gio_inotify_inotify-kernel.c patch-gio_meson.build patch-gio_tests_iptosmessage.c patch-gio_tests_meson.build patch-girepository_gitypelib.c patch-glib_gatomic.c patch-glib_gatomic.h patch-glib_genviron.c patch-glib_glib-unix.c patch-glib_gspawn-posix.c patch-glib_gthread.c patch-glib_tests_hash.c patch-glib_tests_include.c patch-glib_tests_meson.build patch-glib_tests_testing.c patch-glib_tests_thread.c patch-gmodule_gmodule-dl.c patch-gmodule_gmodule.c patch-gobject_glib-mkenums.in patch-gobject_meson.build patch-meson.build patch-meson.options' ;;
            devel/pcre2) approved='' ;;
            graphics/cairo) approved='patch-meson.build patch-src_cairo-bentley-ottmann-rectangular.c patch-src_cairo-colr-glyph-render.c patch-src_cairo-image-surface.c patch-test_pdf-structure.c patch-util_cairo-missing_getline.c' ;;
            fonts/harfbuzz) approved='patch-src_meson.build patch-util_meson.build' ;;
            converters/fribidi) approved='patch-bin_Makefile.am patch-bin_Makefile.in' ;;
            graphics/png) approved='patch-libpng-config.in patch-pngpriv.h' ;;
            graphics/freetype2) approved='patch-builds_unix_freetype-config.in patch-builds_unix_unix-cc.in' ;;
            archivers/lzo) approved='patch-aa patch-src_lzo1f__d.ch' ;;
            devel/glib2-tools) approved='' ;;
            devel/glib2-introspection) approved='' ;;
            devel/gdbus-codegen) approved='patch-meson.build' ;;
            graphics/MesaLib)
                approved='patch-bin_symbols-check.py patch-dso-lifetime patch-include_c99__alloca.h patch-meson-python-selection patch-meson-xcb-pkgconfig patch-src_gallium_auxiliary_vl_vl__csc.c patch-src_util_half__float.c' ;;
            x11/libdrm)
                approved='patch-ac patch-amdgpu_amdgpu__cs.c patch-include_drm_drm.h patch-libsync.h patch-symbols-check.py patch-tests_nouveau_threaded.c patch-xf86drm.c patch-xf86drmMode.c patch-zz-native-identity patch-zzz-native-warnings' ;;
            devel/wayland)
                approved='patch-meson.build patch-meson__options.txt patch-scanner.c patch-src_meson.build patch-src_wayland-os.c patch-tests_client-test.c patch-tests_test-helpers.c' ;;
            devel/wayland-protocols)
                approved='patch-stable_xdg-shell_xdg-shell.xml patch-unstable_xdg-output_xdg-output-unstable-v1.xml' ;;
            wayland/wlroots)
                approved='patch-backend_libinput_meson.build patch-render_allocator_allocator.c patch-render_drm__syncobj.c patch-render_vulkan_vulkan.c patch-software-primary-node patch-util_shm.c patch-xcursor_xcursor.c' ;;
            x11/xkeyboard-config) approved='patch-meson.build' ;;
            x11/libxkbcommon) approved='patch-meson-legacy-root' ;;
            sysutils/hwdata) approved='patch-Makefile' ;;
            sysutils/seatd) approved='patch-common_drm.c patch-common_terminal.c patch-wscons-keyboard-restore' ;;
            x11/libdisplay-info) approved='patch-meson.build' ;;
            devel/libopeninput) approved='patch-src_wscons.c patch-src_wscons.h patch-wscons-absolute-pointer' ;;
            x11/xorgproto|devel/libudev-bsd|devel/input-headers|graphics/libliftoff) approved='' ;;
        esac
        case "$recipe" in
            graphics/MesaLib|x11/libdrm|x11/xkeyboard-config)
                [ -f "$source/builtin.mk" ] || { echo "Missing builtin guard: $recipe" >&2; exit 2; } ;;
            devel/wayland)
                [ -f "$source/cross-scanner.mk" ] && [ -f "$source/platform.mk" ] || exit 2 ;;
            devel/wayland-protocols)
                [ -f "$source/cross-scanner.mk" ] || { echo 'Missing protocols host scanner integration' >&2; exit 2; } ;;
        esac
        if [ "$recipe" = wayland/wlroots ]; then
            [ -f "$source/options.mk" ] || { echo 'Missing wlroots feature selection' >&2; exit 2; }
        fi
        if [ "$recipe" = sysutils/hwdata ]; then
            [ -f "$source/native-meson.mk" ] || { echo "Missing native graphics metadata guard" >&2; exit 2; }
        fi
        if [ "$recipe" = x11/libxkbcommon ] || [ "$recipe" = devel/libopeninput ] || [ "$recipe" = devel/glib2 ] || [ "$recipe" = fonts/harfbuzz ]; then
            [ -f "$source/Makefile.common" ] || { echo 'Missing xkbcommon common recipe' >&2; exit 2; }
        fi
        case "$recipe" in
            devel/glib2-tools|devel/glib2-introspection)
                grep -q '^.include "../../devel/glib2/Makefile.common"' "$source/Makefile" || exit 2
                grep -q '^DISTINFO_FILE=.*../../devel/glib2/distinfo' "$source/Makefile" || exit 2
                continue ;;
        esac
        for name in $approved; do
            grep -q "^SHA1 ($name) = " "$source/distinfo" && [ -f "$source/patches/$name" ] || {
                echo "Missing required graphics patch: $recipe/$name" >&2; exit 2;
            }
        done
        required=$(awk '/^SHA1 \(patch-/ { gsub(/[()]/, "", $2); print $2 }' "$source/distinfo")
        case "$recipe" in
            x11/xorgproto|devel/libudev-bsd|devel/input-headers|graphics/libliftoff|devel/pcre2) ;;
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
    for recipe in graphics/MesaLib x11/libdrm devel/wayland devel/wayland-protocols x11/xorgproto devel/libudev-bsd wayland/wlroots x11/xkeyboard-config devel/input-headers x11/libxkbcommon sysutils/hwdata sysutils/seatd x11/libdisplay-info graphics/libliftoff devel/libopeninput devel/glib2 devel/pcre2 graphics/cairo fonts/harfbuzz converters/fribidi graphics/png graphics/freetype2 archivers/lzo devel/glib2-tools devel/glib2-introspection devel/gdbus-codegen; do
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
