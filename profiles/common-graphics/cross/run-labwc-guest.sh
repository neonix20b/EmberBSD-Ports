#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), two bounded serial-console labwc sessions.
PATH=/rescue:/usr/bin:/bin:/sbin:/usr/pkg/bin
export PATH
ulimit -c 0
fail() { echo "EMBER_LABWC_FAILURE=$*"; halt -p; exit 1; }
verify() {
    while read -r expected path; do
        actual=$(sha256 -q "$path") || return 1
        [ "$actual" = "$expected" ] || return 1
    done < /tests/labwc/runtime.sha256
    echo 'PASS: staged runtime ELF hashes'
}
mount -t tmpfs tmpfs /tmp || fail tmp
mount -t tmpfs tmpfs /var/run || fail run
mount -t tmpfs -o -m1777 tmpfs /var/shm || fail shm
mkdir -p /tmp/home /tmp/runtime /tmp/fontcache || fail directories
chmod 700 /tmp/runtime || fail permissions
unset LD_PRELOAD LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE
HOME=/tmp/home XDG_RUNTIME_DIR=/tmp/runtime XDG_DATA_DIRS=/usr/pkg/share
FONTCONFIG_FILE=/tests/labwc/fonts.conf LIBSEAT_BACKEND=seatd
WLR_DRM_DEVICES=/dev/dri/card0 WLR_RENDERER=gles2 EGL_PLATFORM=wayland
export HOME XDG_RUNTIME_DIR XDG_DATA_DIRS FONTCONFIG_FILE LIBSEAT_BACKEND WLR_DRM_DEVICES WLR_RENDERER EGL_PLATFORM
verify || fail initial-runtime
SEATD_VTBOUND=0 /usr/pkg/bin/seatd -l debug > /tmp/seatd.log 2>&1 &
seatd=$!
sleep 1
result=0
for cycle in 1 2; do
    echo "SESSION_BEGIN=$cycle"
    timeout -k 5 75 /usr/pkg/bin/labwc -d -C /tests/labwc/config -S /tests/labwc/client
    code=$?
    echo "SESSION_EXIT=$cycle,$code"
    if [ "$code" != 0 ]; then result=$code; break; fi
    echo "SESSION_END=$cycle"
done
kill "$seatd" || result=1
wait "$seatd" || result=1
cat /tmp/seatd.log
verify || result=1
echo "EMBER_LABWC_RESULT=$result"
echo EMBER_LABWC_END
halt -p
