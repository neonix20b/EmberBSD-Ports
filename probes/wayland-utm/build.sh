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
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be a positive integer.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Do not fall back to base GCC or retain an older per-application LLVM/Python.
CC=${CC:-/usr/pkg/gcc16/bin/gcc}
CXX=${CXX:-/usr/pkg/gcc16/bin/g++}
LLVM_CONFIG=${LLVM_CONFIG:-/usr/pkg/bin/llvm-config}
PYTHON=${PYTHON:-/usr/pkg/bin/python3.14}
PKG_CONFIG=${PKG_CONFIG:-/usr/pkg/bin/pkg-config}
input=${INPUT_PREFIX:?Set INPUT_PREFIX to the accepted private libopeninput prefix}
for path in "$CC" "$CXX" "$LLVM_CONFIG" "$PYTHON" "$PKG_CONFIG" "$input"; do
    case "$path" in /*) ;; *) echo "Absolute tool/input path required: $path" >&2; exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./+-]*) echo "Unsupported path: $path" >&2; exit 2 ;; esac
done
for tool in ninja tar patch sha256 sed bison flex curl pkg_info readelf ldd nm; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
[ "$("$CC" -dumpfullversion -dumpversion)" = 16.2.0 ] || { echo 'GCC 16.2.0 required.' >&2; exit 2; }
[ "$("$CXX" -dumpfullversion -dumpversion)" = 16.2.0 ] || { echo 'G++ 16.2.0 required.' >&2; exit 2; }
[ "$("$LLVM_CONFIG" --version)" = 23.1.2 ] || { echo 'Common LLVM 23.1.2 required; llvmpipe stays enabled.' >&2; exit 2; }
[ "$("$LLVM_CONFIG" --shared-mode)" = shared ] || { echo 'Shared LLVM required.' >&2; exit 2; }
[ "$("$PYTHON" --version)" = 'Python 3.14.8' ] || { echo 'Common Python 3.14.8 required.' >&2; exit 2; }
[ "$("$PYTHON" -m mesonbuild.mesonmain --version)" = 1.12.1 ] || { echo 'Meson 1.12.1 for the selected Python required.' >&2; exit 2; }
[ -f "$input/lib/pkgconfig/libinput.pc" ] || { echo 'Patched libinput.pc missing.' >&2; exit 2; }
llvm_libdir=$("$LLVM_CONFIG" --libdir)
llvm_libdir=$(CDPATH= cd -- "$llvm_libdir" && pwd -P)
input=$(CDPATH= cd -- "$input" && pwd -P)
cxx_library=$("$CXX" -print-file-name=libstdc++.so)
[ -f "$cxx_library" ] || { echo 'Selected C++ shared runtime missing.' >&2; exit 2; }
cxx_libdir=$(CDPATH= cd -- "$(dirname "$cxx_library")" && pwd -P)
for path in "$llvm_libdir" "$cxx_libdir"; do
    case "$path" in /*) ;; *) echo 'Absolute runtime library directory required.' >&2; exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./+-]*) echo 'Unsupported library path.' >&2; exit 2 ;; esac
done
real_ninja=$(command -v ninja)
mkdir "$work"
mkdir "$work/archives" "$work/src" "$work/log" "$work/tools"
ln -s "$PYTHON" "$work/tools/python3"
printf '#!/bin/sh\nexec "%s" -m mesonbuild.mesonmain "$@"\n' "$PYTHON" > "$work/tools/meson"
# Meson rebuilds test-only targets itself; bound those Ninja invocations too.
printf '#!/bin/sh\nexec "%s" "$@" -j %s\n' "$real_ninja" "$jobs" > "$work/tools/ninja"
chmod 755 "$work/tools/meson" "$work/tools/ninja"
prefix=$work/install
PATH="$work/tools:$PATH"
NINJA="$work/tools/ninja"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$input/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
LD_LIBRARY_PATH="$prefix/lib:$input/lib:$llvm_libdir:$cxx_libdir:/usr/pkg/lib:/usr/X11R7/lib"
CFLAGS="-O2 -I/usr/pkg/include -I/usr/X11R7/include"
CXXFLAGS="$CFLAGS"
LDFLAGS="-L$prefix/lib -Wl,-rpath,$prefix/lib -L$input/lib -Wl,-rpath,$input/lib -L$llvm_libdir -Wl,-rpath,$llvm_libdir -L$cxx_libdir -Wl,-rpath,$cxx_libdir -L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib"
export PATH NINJA CC CXX LLVM_CONFIG PYTHON PKG_CONFIG PKG_CONFIG_PATH LD_LIBRARY_PATH CFLAGS CXXFLAGS LDFLAGS
cat > "$work/tools/native.ini" <<END_NATIVE
[binaries]
c = '$CC'
cpp = '$CXX'
llvm-config = '$LLVM_CONFIG'
pkg-config = '$PKG_CONFIG'
END_NATIVE

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
    printf 'CC=%s\nCXX=%s\nLLVM_CONFIG=%s\nPYTHON=%s\nINPUT_PREFIX=%s\n' "$CC" "$CXX" "$LLVM_CONFIG" "$PYTHON" "$input"
    "$CC" --version
    "$CXX" --version
    "$LLVM_CONFIG" --version --libdir --shared-mode
    meson --version
    "$PYTHON" --version
    "$PKG_CONFIG" --version
    sha256 "$CC" "$CXX" "$LLVM_CONFIG" "$PYTHON" "$cxx_library"
    "$PKG_CONFIG" --modversion libinput
    "$PKG_CONFIG" --variable=libdir libinput
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
        run "$component-$(basename "$p")" patch --fuzz=0 -d "$source" -p0 < "$p"
    done
}
apply_patches libdrm "$work/src/libdrm-2.4.134"
apply_patches mesa "$work/src/mesa-26.2.4"
apply_patches wlroots "$work/src/wlroots-0.19.3"
apply_patches labwc "$work/src/labwc-0.9.7"
# The same substitutions as the pinned pkgsrc recipes, without buildlink.
sed 's/@ATOMIC_OPS_CHECK@/1/g' "$work/src/libdrm-2.4.134/xf86drm.h" > "$work/xf86drm.h"
mv "$work/xf86drm.h" "$work/src/libdrm-2.4.134/xf86drm.h"
sed 's|@PREFIX@|/usr/pkg|g; s|@X11BASE@|/usr/X11R7|g' "$work/src/wlroots-0.19.3/xcursor/xcursor.c" > "$work/xcursor.c"
mv "$work/xcursor.c" "$work/src/wlroots-0.19.3/xcursor/xcursor.c"

run libdrm-setup env LDFLAGS="$LDFLAGS -lpci" meson setup "$work/drm-build" "$work/src/libdrm-2.4.134" \
    --native-file="$work/tools/native.ini" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
    -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dfreedreno=disabled \
    -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled -Dman-pages=disabled \
    -Dcairo-tests=disabled -Dtests=true -Dinstall-test-programs=true
run libdrm-build meson compile -C "$work/drm-build" -j "$jobs"
run libdrm-test meson test -C "$work/drm-build" --no-rebuild --num-processes "$jobs" --print-errorlogs
run libdrm-install meson install -C "$work/drm-build" --no-rebuild

[ "$("$PKG_CONFIG" --variable=libdir libdrm)" = "$prefix/lib" ] || { echo 'libdrm escaped the matched prefix.' >&2; exit 2; }
[ "$("$PKG_CONFIG" --variable=libdir libinput)" = "$input/lib" ] || { echo 'libinput escaped its selected prefix.' >&2; exit 2; }
run mesa-setup meson setup "$work/mesa-build" "$work/src/mesa-26.2.4" \
    --native-file="$work/tools/native.ini" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    --sysconfdir=/usr/pkg/etc \
    -Dgallium-drivers=virgl,softpipe,llvmpipe -Dvulkan-drivers= -Dvulkan-layers= \
    -Dplatforms=x11,wayland -Dglx=dri -Degl=enabled -Dgbm=enabled \
    -Dglvnd=disabled -Dgles1=enabled -Dgles2=enabled -Dopengl=true \
    -Dllvm=enabled -Dshared-llvm=enabled -Dllvm-orcjit=true \
    -Dgallium-va=disabled -Dgallium-mediafoundation=disabled \
    -Dgallium-rusticl=false -Dteflon=false -Dtools= -Dperfetto=false \
    -Dspirv-tools=disabled -Dmicrosoft-clc=disabled -Dallow-fallback-for= \
    -Dbuild-tests=true
run mesa-dependencies meson introspect --dependencies "$work/mesa-build"
run mesa-atexit sh "$recipe/tests/mesa-atexit.sh" "$work/src/mesa-26.2.4" "$work/atexit-test"
run mesa-half sh "$recipe/tests/mesa-half.sh" "$work/src/mesa-26.2.4" "$work/half-test"
run mesa-symbols sh "$recipe/tests/mesa-symbols.sh" "$work/src/mesa-26.2.4" "$work/symbols-test"
run mesa-build meson compile -C "$work/mesa-build" -j "$jobs"
# Meson builds its non-default test prerequisites through the bounded Ninja.
run mesa-test meson test -C "$work/mesa-build" --num-processes "$jobs" --print-errorlogs
run mesa-install meson install -C "$work/mesa-build" --no-rebuild

run wlroots-setup meson setup "$work/wlroots-build" "$work/src/wlroots-0.19.3" \
    --native-file="$work/tools/native.ini" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dbackends=drm,libinput,x11 -Drenderers=gles2,pixman -Dallocators=gbm \
    -Dsession=enabled -Dxwayland=disabled -Dexamples=false -Dlibliftoff=disabled
run wlroots-build meson compile -C "$work/wlroots-build" -j "$jobs"
run wlroots-test meson test -C "$work/wlroots-build" --no-rebuild --num-processes "$jobs" --print-errorlogs
run wlroots-install meson install -C "$work/wlroots-build" --no-rebuild

CFLAGS="$CFLAGS -I/usr/pkg/include/libepoll-shim"
export CFLAGS
run labwc-setup meson setup "$work/labwc-build" "$work/src/labwc-0.9.7" \
    --native-file="$work/tools/native.ini" \
    --prefix="$prefix" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dxwayland=disabled -Dman-pages=disabled -Dtest=enabled
run labwc-build meson compile -C "$work/labwc-build" -j "$jobs"
run labwc-test meson test -C "$work/labwc-build" --no-rebuild --num-processes "$jobs" --print-errorlogs
run labwc-install meson install -C "$work/labwc-build" --no-rebuild
run graphics-link-audit sh "$recipe/audit-libraries.sh" "$prefix" "$llvm_libdir" "$cxx_libdir" "$input" \
    "$prefix/bin/labwc" "$prefix/lib/libwlroots-0.19.so"
printf 'Private build installed at %s. Native KMS and GPU runtime are not implied.\n' "$prefix"
