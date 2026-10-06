#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 EmberBSD contributors. AI-assisted build probe.
set -eu

usage() {
    echo "Usage: sh probe.sh modemmanager|networkmanager [archive-directory]" >&2
    exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
component=$1
archives=${2:-}
case "$component" in
    modemmanager)
        source_name=ModemManager-1.24.2
        digest=fbc75adcc0d7b0565f256e7ff4e8872b0a37c4413ff576665f7470932d9c1b68
        url=https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/archive/1.24.2/ModemManager-1.24.2.tar.gz
        patch_name=modemmanager-client-only.patch
        ;;
    networkmanager)
        source_name=NetworkManager-1.54.3
        digest=16c1e954a8598a0afc71c9936a7e4f0ad949522438d96fec63aa1abb6f2207fe
        url=https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/archive/1.54.3/NetworkManager-1.54.3.tar.gz
        patch_name=networkmanager-client-scope.patch
        ;;
    *) usage ;;
esac

[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 1; }
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case ${JOBS:-2} in 1|2) jobs=${JOBS:-2} ;; *) echo 'JOBS must be 1 or 2.' >&2; exit 2 ;; esac
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/bin
export PATH
python=${PYTHON:-/usr/pkg/bin/python3.13}
pkg_config=${PKG_CONFIG:-}
[ -x "$python" ] || { echo "Missing upstream Python interpreter: $python" >&2; exit 1; }

mkdir -p "$HOME/.cache"
if [ -n "${WORK_DIR:-}" ]; then
    case "$WORK_DIR" in /*) ;; *) echo 'WORK_DIR must be absolute.' >&2; exit 2 ;; esac
    mkdir "$WORK_DIR"
    work=$WORK_DIR
else
    work=$(mktemp -d "$HOME/.cache/emberbsd-phosh-$component.XXXXXXXX")
fi
echo "Probe directory: $work"
mkdir "$work/downloads" "$work/src" "$work/logs" "$work/tools"
ln -s "$python" "$work/tools/python3"
if [ -z "$pkg_config" ]; then
    cp "$script_dir/../native-pkg-config.sh" "$work/tools/pkg-config"
    chmod 755 "$work/tools/pkg-config"
    pkg_config=$work/tools/pkg-config
fi
[ -x "$pkg_config" ] || { echo "Missing pkg-config: $pkg_config" >&2; exit 1; }
PKG_CONFIG=$pkg_config
export PKG_CONFIG
PATH=$work/tools:$PATH
export PATH
prefix=$work/prefix
archive=$work/downloads/$source_name.tar.gz
if [ -n "$archives" ]; then
    cp "$archives/$source_name.tar.gz" "$archive"
else
    curl -fL --retry 2 -o "$archive" "$url"
fi
actual=$(sha256 -q "$archive")
[ "$actual" = "$digest" ] || { echo "SHA256 mismatch: $archive" >&2; exit 1; }
tar -xf "$archive" -C "$work/src"
cd "$work/src/$source_name"
patch -p1 < "$script_dir/$patch_name"

run_logged() {
    stage=$1
    shift
    if "$@" > "$work/logs/$stage.log" 2>&1; then
        echo "$stage: passed"
    else
        result=$?
        tail -n 60 "$work/logs/$stage.log" >&2
        echo "$stage: failed ($result); full log: $work/logs/$stage.log" >&2
        exit "$result"
    fi
}

if [ "$component" = modemmanager ]; then
    run_logged configure meson setup "$work/build" --prefix "$prefix" \
        --libdir lib --wrap-mode=nodownload -Dclient_only=true \
        -Dudev=false -Dudevdir="$prefix/lib/udev" \
        -Dsystemdsystemunitdir=no -Dsystemd_suspend_resume=false \
        -Dsystemd_journal=false -Dpolkit=no -Dmbim=false -Dqmi=false \
        -Dqrtr=false -Dman=false -Dbash_completion=false -Dexamples=false \
        -Dintrospection=true -Dvapi=false -Dtests=true
    run_logged build meson compile -C "$work/build" -j "$jobs"
    run_logged test meson test -C "$work/build" --no-rebuild --print-errorlogs
    run_logged install meson install -C "$work/build" --no-rebuild
    PKG_CONFIG_PATH=$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
    LD_LIBRARY_PATH=$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export PKG_CONFIG_PATH LD_LIBRARY_PATH
    # pkg-config output is deliberately split into compiler arguments.
    run_logged smoke-build cc $("$pkg_config" --cflags mm-glib) \
        "$script_dir/mm-client-smoke.c" -o "$work/mm-client-smoke" \
        $("$pkg_config" --libs mm-glib)
    run_logged smoke-ldd ldd "$work/mm-client-smoke"
    if ! grep -q '/usr/lib/libintl.so.1' "$work/logs/smoke-ldd.log" ||
        grep -q 'libintl.so.8' "$work/logs/smoke-ldd.log"; then
        echo 'Unexpected gettext ABI; inspect logs/smoke-ldd.log.' >&2
        exit 1
    fi
    echo "Library version: $("$pkg_config" --modversion mm-glib)"
    echo "Run $work/mm-client-smoke to inspect the system bus without starting a service."
    echo 'Exit 77 means the library works but no ModemManager service owns the bus name.'
else
    run_logged configure meson setup "$work/build" --prefix "$prefix" \
        --libdir lib --wrap-mode=nodownload -Dclient_only=true \
        -Dsystemd_journal=false -Dsession_tracking=no -Dselinux=false \
        -Dlibaudit=no -Dppp=false -Dmodem_manager=false -Dnmcli=false \
        -Dnmtui=false -Dnm_cloud_setup=false -Dnbft=false -Ddocs=false \
        -Dtests=no -Dqt=false -Dvapi=false -Dsystemdsystemunitdir=no \
        -Dudev_dir=no -Dpolkit=false -Dintrospection=false
    run_logged build meson compile -C "$work/build" -j "$jobs"
    echo 'Compilation completed; this diagnostic probe does not install unvalidated libnm.'
fi
echo "PKG_CONFIG_PATH=$prefix/lib/pkgconfig"
echo "LD_LIBRARY_PATH=$prefix/lib"
echo "GI_TYPELIB_PATH=$prefix/lib/girepository-1.0"
