#!/bin/sh
# Origin: EmberBSD; AI-assisted native Wayland/VirGL build probe.
set -eu
umask 022
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/bin
export PATH

[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD build required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: sh build.sh ABSOLUTE_NEW_DIRECTORY [ARCHIVE_DIRECTORY]' >&2; exit 2; }
work=$1
archives=${2:-}
case "$work" in /*) ;; *) echo 'Build directory must be absolute.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a build path without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
jobs=${JOBS:-3}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be a positive integer.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for tool in cc c++ meson ninja pkg-config tar patch sha256 sed bison flex; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
python=${PYTHON:-/usr/pkg/bin/python3.13}
[ -x "$python" ] || { echo 'Upstream Meson and Mesa need Python 3.13 and Mako.' >&2; exit 2; }
mkdir "$work"
mkdir "$work/archives" "$work/src" "$work/log" "$work/tools"
ln -s "$python" "$work/tools/python3"
prefix=$work/install
PATH="$work/tools:$PATH"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
CFLAGS="-O2 -I/usr/pkg/include -I/usr/X11R7/include -Dalloca=__builtin_alloca -DHAVE_NOATEXIT"
CXXFLAGS="$CFLAGS"
LDFLAGS="-L$prefix/lib -Wl,-rpath,$prefix/lib -L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib"
export PATH PKG_CONFIG_PATH LD_LIBRARY_PATH CFLAGS CXXFLAGS LDFLAGS

run()
{
    label=$1
    shift
    printf '%s\n' "$label"
    status=0
    "$@" > "$work/log/$label.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        tail -80 "$work/log/$label.log" >&2
        printf 'Stage %s failed (%s); logs: %s/log\n' "$label" "$status" "$work" >&2
        exit "$status"
    fi
}

{
    uname -a
    cc --version
    meson --version
    "$python" --version
    pkg_info
} > "$work/log/environment.txt" 2>&1

while read -r name expected url; do
    if [ -n "$archives" ]; then
        cp "$archives/$name" "$work/archives/$name"
    else
        curl -fLsS --connect-timeout 20 --max-time 300 "$url" -o "$work/archives/$name"
    fi
    actual=$(sha256 -q "$work/archives/$name")
    [ "$actual" = "$expected" ] || { echo "SHA256 mismatch: $name" >&2; exit 2; }
    printf '%s  %s  %s\n' "$actual" "$name" "$url" >> "$work/log/sources.txt"
    tar -xf "$work/archives/$name" -C "$work/src"
done < "$recipe/sources.tsv"

apply_patches()
{
    component=$1
    source=$2
    for p in "$recipe/patches/$component"/*; do
        run "$component-$(basename "$p")" patch -d "$source" -p0 < "$p"
    done
}
apply_patches libdrm "$work/src/libdrm-2.4.134"
apply_patches mesa "$work/src/mesa-21.3.9"
apply_patches wlroots "$work/src/wlroots-0.19.3"
apply_patches labwc "$work/src/labwc-0.9.7"
# The same substitutions as the pinned pkgsrc recipes, without buildlink.
sed 's/@ATOMIC_OPS_CHECK@/1/g' "$work/src/libdrm-2.4.134/xf86drm.h" > "$work/xf86drm.h"
mv "$work/xf86drm.h" "$work/src/libdrm-2.4.134/xf86drm.h"
sed 's|@PREFIX@|/usr/pkg|g; s|@X11BASE@|/usr/X11R7|g' "$work/src/wlroots-0.19.3/xcursor/xcursor.c" > "$work/xcursor.c"
mv "$work/xcursor.c" "$work/src/wlroots-0.19.3/xcursor/xcursor.c"

run libdrm-setup env LDFLAGS="$LDFLAGS -lpci" meson setup "$work/drm-build" "$work/src/libdrm-2.4.134" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
    -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dfreedreno=disabled \
    -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled -Dman-pages=disabled \
    -Dcairo-tests=disabled -Dtests=true -Dinstall-test-programs=true
run libdrm-build meson compile -C "$work/drm-build" -j "$jobs"
run libdrm-test meson test -C "$work/drm-build" --no-rebuild --print-errorlogs
run libdrm-install meson install -C "$work/drm-build" --no-rebuild

run mesa-setup meson setup "$work/mesa-build" "$work/src/mesa-21.3.9" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    --sysconfdir=/usr/pkg/etc \
    -Dgallium-drivers=virgl,swrast -Ddri-drivers= -Dvulkan-drivers= \
    -Dplatforms=x11,wayland -Dglx=dri -Degl=enabled -Dgbm=enabled \
    -Dgles1=enabled -Dgles2=enabled -Dshared-glapi=enabled -Dllvm=disabled \
    -Dgallium-vdpau=disabled -Dgallium-xvmc=disabled -Dgallium-omx=disabled \
    -Dgallium-va=disabled -Dgallium-xa=disabled -Dgallium-opencl=disabled \
    -Dbuild-tests=true
run mesa-build meson compile -C "$work/mesa-build" -j "$jobs"
# Some upstream test executables are build_by_default:false. Let Meson build
# its test prerequisites before running them.
run mesa-test meson test -C "$work/mesa-build" --print-errorlogs
run mesa-install meson install -C "$work/mesa-build" --no-rebuild

run wlroots-setup meson setup "$work/wlroots-build" "$work/src/wlroots-0.19.3" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dbackends=drm,libinput,x11 -Drenderers=gles2 -Dallocators=gbm \
    -Dsession=enabled -Dxwayland=disabled -Dexamples=false -Dlibliftoff=disabled
run wlroots-build meson compile -C "$work/wlroots-build" -j "$jobs"
run wlroots-test meson test -C "$work/wlroots-build" --no-rebuild --print-errorlogs
run wlroots-install meson install -C "$work/wlroots-build" --no-rebuild

CFLAGS="$CFLAGS -I/usr/pkg/include/libepoll-shim"
export CFLAGS
run labwc-setup meson setup "$work/labwc-build" "$work/src/labwc-0.9.7" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dxwayland=disabled -Dman-pages=disabled -Dtest=enabled
run labwc-build meson compile -C "$work/labwc-build" -j "$jobs"
run labwc-test meson test -C "$work/labwc-build" --no-rebuild --print-errorlogs
run labwc-install meson install -C "$work/labwc-build" --no-rebuild
printf 'Private build installed at %s. Native KMS and GPU runtime are not implied.\n' "$prefix"
