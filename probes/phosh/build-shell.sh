#!/bin/sh
# Build Phosh with explicitly unavailable Linux platform/network integrations.
set -eu
umask 077
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/bin
LANG=C.UTF-8
export PATH LANG
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD build required.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build as an ordinary user.' >&2; exit 2; }
[ "$#" -ge 3 ] && [ "$#" -le 4 ] || { echo 'Usage: sh build-shell.sh NEW_WORK_DIRECTORY SUPPORT_PREFIX PHOC_PREFIX [PHOSH_ARCHIVE]' >&2; exit 2; }
work=$1
support=$2
phoc=$3
for path in "$work" "$support" "$phoc"; do
    case "$path" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./-]*) echo 'Use paths without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
done
jobs=${JOBS:-2}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be a positive integer.' >&2; exit 2 ;; esac
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
for tool in cc meson ninja tar patch sha256 xsltproc; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
python=${PYTHON:-/usr/pkg/bin/python3.13}
[ -x "$python" ] || { echo 'An upstream Python 3 interpreter is required.' >&2; exit 2; }
case "$python" in /*) ;; *) echo 'PYTHON must be absolute.' >&2; exit 2 ;; esac
mkdir "$work"
mkdir "$work/tools" "$work/logs"
ln -s "$python" "$work/tools/python3"
cp "$recipe/native-pkg-config.sh" "$work/tools/pkg-config"
chmod 755 "$work/tools/pkg-config"
PATH="$work/tools:$support/bin:$phoc/bin:$PATH"
PKG_CONFIG="$work/tools/pkg-config"
PKG_CONFIG_PATH="$support/lib/pkgconfig:$phoc/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
LD_LIBRARY_PATH="$support/lib:$phoc/lib:/usr/pkg/lib:/usr/X11R7/lib"
CFLAGS='-O2 -I/usr/pkg/include -I/usr/X11R7/include'
LDFLAGS="-L/usr/lib -L$support/lib -Wl,-rpath,$support/lib -L$phoc/lib -Wl,-rpath,$phoc/lib -L/usr/pkg/lib -Wl,-rpath,/usr/pkg/lib -L/usr/X11R7/lib -Wl,-rpath,/usr/X11R7/lib"
export PATH PKG_CONFIG PKG_CONFIG_PATH LD_LIBRARY_PATH CFLAGS LDFLAGS
run()
{
    stage=$1
    shift
    printf '%s\n' "$stage"
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        tail -70 "$work/logs/$stage.log" >&2
        printf 'Stage %s failed (%s). Logs: %s/logs\n' "$stage" "$status" "$work" >&2
        exit "$status"
    fi
}
url=https://sources.phosh.mobi/releases/phosh/phosh-0.58.0.tar.xz
archive=$work/phosh-0.58.0.tar.xz
if [ "$#" -eq 4 ]; then
    cp "$4" "$archive"
else
    curl -fLsS --connect-timeout 20 --max-time 300 "$url" -o "$archive"
fi
expected=b936af34ebed15b29d4f941c48aa328a47da9c2e51cbf6ef89040a90f522ed73
[ "$(sha256 -q "$archive")" = "$expected" ] || { echo 'Phosh SHA256 mismatch.' >&2; exit 2; }
printf '%s %s\n' "$expected" "$url" > "$work/logs/source.txt"
tar -xJf "$archive" -C "$work"
src=$work/phosh-0.58.0
run platform-patch patch -d "$src" -p1 < "$recipe/platform/phosh-optional-platform.patch"
run networkmanager-patch patch -d "$src" -p1 < "$recipe/platform/phosh-optional-networkmanager.patch"
run portable-patch patch -d "$src" -p1 < "$recipe/platform/phosh-portable-build.patch"
run keybindings-patch patch -d "$src" -p1 < "$recipe/platform/phosh-optional-keybindings.patch"
run hks-test sh "$recipe/platform/test-hks-unavailable.sh" "$src"
run configure meson setup "$work/build" "$src" \
    --prefix="$work/install" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dlogind=disabled -Drfkill=disabled -Dnetworkmanager=disabled \
    -Dcompositor="$phoc/bin/phoc" -Dtests=false -Dphoc_tests=disabled -Dgtk_doc=false -Dman=false \
    -Dlockscreen-plugins=false -Dquick-setting-plugins=false -Dstatus-icon-plugins=false
run compile meson compile -C "$work/build" -j "$jobs"
run install meson install -C "$work/build" --no-rebuild
run abi ldd "$work/install/libexec/phosh"
if grep -q 'libintl.so.8' "$work/logs/abi.log"; then
    echo 'Conflicting gettext ABI detected.' >&2
    exit 1
fi
printf '%s\n' "$support" > "$work/support-prefix.txt"
printf '%s\n' "$phoc" > "$work/phoc-prefix.txt"
printf 'Phosh built at %s/install. Run the nested session to validate runtime.\n' "$work"
