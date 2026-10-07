#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# AI-assisted native check of the pinned pkgsrc rc.d script, without installation.
set -eu
umask 077
[ "$(uname -s)" = NetBSD ] || { echo 'Native NetBSD/EmberBSD required.' >&2; exit 2; }
[ "$#" -eq 3 ] || { echo 'Usage: test-rc-service.sh INSTALL_PREFIX PKGSRC_ROOT NEW_WORK' >&2; exit 2; }
prefix=$1
pkgsrc=$2
work=$3
for directory in "$prefix" "$pkgsrc" "$work"; do
    case "$directory" in /*) ;; *) exit 2 ;; esac
    case "$directory" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
done
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
# rc.subr can also load a per-service system override. Never run a foreign one.
[ ! -e /etc/rc.conf.d/mosquitto ] && [ ! -L /etc/rc.conf.d/mosquitto ] || {
    echo 'A system mosquitto rc override exists; isolated check refused.' >&2; exit 2
}
original=$pkgsrc/net/mosquitto/files/mosquitto.sh
[ "$(sha256 -q "$original")" = 46f0a0ff3bbb403ae38c14985caa7912a2f7cad21c730c4ba5877cad43d83780 ] || {
    echo 'Use the rc script from pinned pkgsrc fff4deb639a1a640476203c80f752fb77b6cb14b.' >&2
    exit 2
}
port=${MQTT_RC_TEST_PORT:-28885}
case "$port" in ''|*[!0-9]*) exit 2 ;; esac
[ "$port" -ge 1024 ] && [ "$port" -le 65535 ] || exit 2
owner=$(id -un)
group=$(id -gn)
for file in sbin/mosquitto bin/mosquitto_pub bin/mosquitto_sub bin/mosquitto_passwd; do
    [ -x "$prefix/$file" ] || { echo "Missing installed program: $file" >&2; exit 2; }
done
mkdir "$work"
mkdir "$work/etc" "$work/var" "$work/var/run" "$work/persistence" "$work/client-config"
XDG_CONFIG_HOME=$work/client-config
export XDG_CONFIG_HOME
# These are the same packaging substitutions, with private test locations.
sed -e 's|@RCD_SCRIPTS_SHELL@|/bin/sh|g' -e 's|@SYSCONFBASE@|/etc|g' \
    -e "s|@PREFIX@|$prefix|g" -e "s|@PKG_SYSCONFDIR@|$work/etc|g" \
    -e "s|@VARBASE@|$work/var|g" -e "s|@MOSQUITTO_USER@|$owner|g" \
    -e "s|@MOSQUITTO_GROUP@|$group|g" "$original" > "$work/mosquitto.rc"
! grep '@[A-Z_]*@' "$work/mosquitto.rc" >/dev/null || exit 2
chmod 700 "$work/mosquitto.rc"
pidfile=$work/var/run/mosquitto/mosquitto.pid
rc()
{
    # rc.subr's loaded-state variable avoids system rc.conf input.
    # The actual rc.subr and all service functions still run unmodified.
    env -i HOME="$work" PATH=/usr/bin:/usr/sbin:/bin:/sbin LC_ALL=C \
        _rc_conf_loaded=true mosquitto=YES \
        /bin/sh "$work/mosquitto.rc" "$1"
}
cleanup()
{
    if [ -f "$pidfile" ]; then rc onestop >> "$work/cleanup.log" 2>&1 || :; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
pass()
{
    printf 'PASS: %s\n' "$1" | tee -a "$work/results.txt"
}
require_stopped()
{
    if kill -0 "$1" 2>/dev/null; then
        echo "Owned broker PID $1 is still running." >&2
        exit 1
    fi
}
"$prefix/bin/mosquitto_passwd" -b -c "$work/passwords" service fixture-service
cat > "$work/etc/mosquitto.conf" <<EOF
pid_file $pidfile
listener $port 127.0.0.1
allow_anonymous false
password_file $work/passwords
persistence true
persistence_location $work/persistence/
log_dest file $work/broker.log
log_type all
EOF
ready()
{
    attempt=0
    until [ -s "$pidfile" ] && rc status > "$work/status.log" 2>&1; do
        [ "$attempt" -lt 10 ] || { echo 'Owned rc service did not start.' >&2; return 1; }
        attempt=$((attempt + 1))
        sleep 1
    done
    owned_pid=$(cat "$pidfile")
    case "$owned_pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$owned_pid"
}
rc start > "$work/start.log" 2>&1
ready
first_pid=$owned_pid
pass 'original pkgsrc rc.d start and status'
"$prefix/bin/mosquitto_pub" -h 127.0.0.1 -p "$port" -V mqttv5 \
    -u service -P fixture-service -q 1 -t ember/service/state -m restored -r
actual=$("$prefix/bin/mosquitto_sub" -h 127.0.0.1 -p "$port" -V mqttv5 \
    -u service -P fixture-service -t ember/service/state -C 1 -W 5)
[ "$actual" = restored ]
pass 'authenticated MQTT through rc.d-started broker'
rc restart > "$work/restart.log" 2>&1
ready
[ "$first_pid" != "$owned_pid" ]
require_stopped "$first_pid"
[ -s "$work/persistence/mosquitto.db" ]
actual=$("$prefix/bin/mosquitto_sub" -h 127.0.0.1 -p "$port" -V mqttv5 \
    -u service -P fixture-service -t ember/service/state -C 1 -W 5)
[ "$actual" = restored ]
pass 'rc.d restart replaces process and restores retained state'
rc stop > "$work/stop.log" 2>&1
require_stopped "$owned_pid"
if rc status > "$work/stopped-status.log" 2>&1; then
    echo 'Stopped service still reports running.' >&2; exit 1
fi
pass 'rc.d stop and stopped status'
echo 'Private rc.d lifecycle passed; package installation and boot remain unverified.'
