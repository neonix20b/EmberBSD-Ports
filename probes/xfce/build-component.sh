#!/bin/sh
# Build one prepared component; all components share one private prefix.
set -eu
umask 077
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin:/usr/bin:/bin
LANG=C.UTF-8
export PATH LANG
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" = 2 ] || { echo 'Usage: sh build-component.sh WORK COMPONENT' >&2; exit 2; }
work=$1
component=$2
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple work path.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
cmp "$recipe/sources.tsv" "$work/sources.tsv" || { echo 'Prepared source manifest differs.' >&2; exit 2; }
entry=$(awk -v id="$component" '$1 == id { print $2, $3 }' "$recipe/sources.tsv")
[ -n "$entry" ] || { echo "Unknown component: $component" >&2; exit 2; }
read -r archive expected <<EOF
$entry
EOF
[ "$(sha256 -q "$work/archives/$archive")" = "$expected" ] || { echo 'Archive checksum mismatch.' >&2; exit 2; }
source=$work/src/${archive%%.tar.*}
[ -d "$source" ] || { echo "Missing prepared source: $source" >&2; exit 2; }
prefix=$work/install
build=$work/build/$component
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || { echo 'JOBS must be positive.' >&2; exit 2; }
CC=${CC:-/usr/pkg/gcc16/bin/gcc}
CXX=${CXX:-/usr/pkg/gcc16/bin/g++}
PYTHON=${PYTHON:-/usr/pkg/bin/python3.13}
for tool in "$CC" "$CXX" "$PYTHON" gmake meson ninja pkg-config msgfmt xsltproc patch; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
case "$PYTHON" in /*) ;; *) echo 'PYTHON must be an absolute executable path.' >&2; exit 2 ;; esac
case "$PYTHON" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple PYTHON path.' >&2; exit 2 ;; esac
cp "$recipe/native-pkg-config.sh" "$work/tools/pkg-config"
chmod 755 "$work/tools/pkg-config"
# Upstream generators ask for python3; point at the one installed interpreter.
ln -sf "$PYTHON" "$work/tools/python3"
PATH="$work/tools:$prefix/bin:$PATH"
PKG_CONFIG="$work/tools/pkg-config"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/share/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
XDG_DATA_DIRS="$prefix/share:/usr/pkg/share:/usr/share"
CFLAGS=${CFLAGS:--O2}
CXXFLAGS=${CXXFLAGS:--O2}
CPPFLAGS="${CPPFLAGS:-} -I$prefix/include -I/usr/pkg/include -I/usr/X11R7/include"
LDFLAGS="${LDFLAGS:-} -L$prefix/lib -Wl,-rpath,$prefix/lib -L/usr/lib -L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib"
export PATH CC CXX PYTHON PKG_CONFIG PKG_CONFIG_PATH LD_LIBRARY_PATH XDG_DATA_DIRS CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
run()
{
    stage=$1
    shift
    printf '%s: %s\n' "$component" "$stage"
    status=0
    "$@" > "$work/logs/$component-$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        tail -60 "$work/logs/$component-$stage.log" >&2
        printf '%s %s failed (%s); see %s/logs\n' "$component" "$stage" "$status" "$work" >&2
        exit "$status"
    fi
}
autotools()
{
    mkdir -p "$build"
    cd "$build"
    run configure "$source/configure" --prefix="$prefix" --sysconfdir="$prefix/etc" \
        --libdir="$prefix/lib" --disable-static "$@"
    run build gmake -j "$jobs"
    run install gmake install
}
meson_build()
{
    if [ -f "$build/meson-private/coredata.dat" ]; then
        run configure meson setup --reconfigure "$build" "$source" "$@"
    else
        run configure meson setup "$build" "$source" --prefix="$prefix" \
            --sysconfdir="$prefix/etc" --libdir=lib --buildtype=release --wrap-mode=nodownload "$@"
    fi
    run build meson compile -C "$build" -j "$jobs"
    run install meson install -C "$build" --no-rebuild
}
reuse_dependency()
{
    module=$1
    version=$2
    if "$PKG_CONFIG" --exists "$module"; then
        actual=$("$PKG_CONFIG" --modversion "$module")
        [ "$actual" = "$version" ] || { echo "$module $actual already installed; update the shared dependency to $version instead of adding a parallel version." >&2; exit 2; }
        printf 'Using existing %s %s\n' "$module" "$actual" | tee "$work/logs/$component-reused.log"
        exit 0
    fi
}
{
    uname -a
    "$CC" --version
    "$CXX" --version
    meson --version
    printf 'CFLAGS=%s\nCPPFLAGS=%s\nLDFLAGS=%s\n' "$CFLAGS" "$CPPFLAGS" "$LDFLAGS"
} > "$work/logs/$component-tools.txt"
case "$component" in
libwnck)
    reuse_dependency libwnck-3.0 43.3
    meson_build -Dintrospection=disabled -Dinstall_tools=false -Dstartup_notification=enabled -Dgtk_doc=false ;;
yaml)
    reuse_dependency yaml-0.1 0.2.5
    autotools
    run check gmake check ;;
xfce4-dev-tools)
    # Retain upstream generators, with the native interpreter paths.
    sed "1s|.*|#!$PYTHON|" "$source/scripts/xdt-gen-visibility" > "$work/tools/xdt-gen-visibility"
    cp "$work/tools/xdt-gen-visibility" "$source/scripts/xdt-gen-visibility"
    autotools ;;
libxfce4util|xfconf)
    autotools --disable-introspection --disable-vala --disable-gtk-doc --disable-debug ;;
libxfce4ui)
    autotools --enable-x11 --disable-wayland --disable-glibtop \
        --disable-introspection --disable-vala --disable-gtk-doc --disable-debug ;;
libxfce4windowing)
    meson_build -Dx11=enabled -Dwayland=disabled -Dintrospection=false -Dvala=disabled -Dtests=false -Dgtk-doc=false ;;
exo)
    autotools --disable-gtk-doc --disable-debug ;;
garcon)
    autotools --disable-introspection --disable-gtk-doc --disable-debug ;;
xfce4-panel)
    meson_build -Dx11=enabled -Dwayland=disabled -Dgtk-layer-shell=disabled \
        -Ddbusmenu=disabled -Dintrospection=false -Dvala=disabled -Dgtk-doc=false ;;
thunar)
    autotools --disable-introspection --disable-gtk-doc --disable-gudev --disable-debug ;;
xfce4-settings)
    sed "1s|.*|#!$PYTHON|" "$source/dialogs/mime-settings/helpers/xfce4-compose-mail" > "$work/tools/xfce4-compose-mail"
    cp "$work/tools/xfce4-compose-mail" "$source/dialogs/mime-settings/helpers/xfce4-compose-mail"
    autotools --enable-x11 --disable-wayland --disable-colord --disable-upower-glib --enable-sound-settings --disable-debug ;;
xfdesktop)
    autotools --enable-x11 --disable-wayland --disable-debug ;;
xfwm4)
    autotools --enable-compositor --enable-startup-notification --disable-debug ;;
xfce4-session)
    autotools --enable-x11 --disable-wayland --disable-polkit --disable-debug \
        --with-xsession-prefix="$prefix" ;;
xfce4-appfinder)
    autotools --disable-debug ;;
mousepad)
    meson_build -Dgtksourceview4=enabled -Dpolkit=disabled -Dkeyfile-settings=true -Dgspell-plugin=disabled ;;
esac
licenses=$prefix/share/xfce-probe/provenance/$component
mkdir -p "$licenses"
for license in "$source"/COPYING* "$source"/LICENSE* "$source"/License "$source"/AUTHORS*; do
    [ ! -f "$license" ] || cp "$license" "$licenses/"
done
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$prefix/share/xfce-probe/provenance/"
find "$prefix" -type f \( -perm -4000 -o -perm -2000 \) -print > "$work/logs/$component-setid.txt"
[ ! -s "$work/logs/$component-setid.txt" ] || { echo 'Unexpected setid file in private prefix.' >&2; exit 1; }
printf '%s installed in %s\n' "$component" "$prefix"
