#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# AI-assisted installed MQTT workflow; all credentials are disposable fixtures.
set -eu
umask 077
[ "$#" -eq 2 ] || { echo 'Usage: test.sh INSTALL_PREFIX NEW_TEST_DIRECTORY' >&2; exit 2; }
prefix=$1
work=$2
case "$prefix:$work" in *[!a-zA-Z0-9_./:-]*) echo 'Use simple absolute paths.' >&2; exit 2 ;; esac
case "$prefix" in /*) ;; *) exit 2 ;; esac
case "$work" in /*) ;; *) exit 2 ;; esac
port=${MQTT_TEST_PORT:-28883}
tls_port=${MQTT_TEST_TLS_PORT:-28884}
for value in "$port" "$tls_port"; do
    case "$value" in ''|*[!0-9]*) exit 2 ;; esac
    [ "$value" -ge 1024 ] && [ "$value" -le 65535 ] || exit 2
done
[ "$port" -ne "$tls_port" ] || exit 2
for file in sbin/mosquitto bin/mosquitto_pub bin/mosquitto_sub bin/mosquitto_passwd; do
    [ -x "$prefix/$file" ] || { echo "Missing installed program: $file" >&2; exit 2; }
done
mkdir "$work"
mkdir "$work/persistence" "$work/client-config"
# User client defaults can inject credentials or --insecure before CLI options.
# Keep HOME intact, but give this test a new empty XDG configuration directory.
XDG_CONFIG_HOME=$work/client-config
export XDG_CONFIG_HOME
broker_pid=
cleanup()
{
    if [ -n "$broker_pid" ]; then
        kill -TERM "$broker_pid" 2>/dev/null || :
        wait "$broker_pid" 2>/dev/null || :
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
pass()
{
    printf 'PASS: %s\n' "$1" | tee -a "$work/results.txt"
}
"$prefix/bin/mosquitto_passwd" -b -c "$work/passwords" operator fixture-operator
"$prefix/bin/mosquitto_passwd" -b "$work/passwords" observer fixture-observer
cat > "$work/acl" <<'EOF'
user operator
topic readwrite ember/test/#
user observer
topic read ember/test/#
EOF
cat > "$work/openssl.cnf" <<'EOF'
[req]
distinguished_name = req_dn
[req_dn]
EOF
openssl req -new -x509 -newkey rsa:2048 -nodes -days 1 \
    -config "$work/openssl.cnf" \
    -subj /CN=localhost -addext subjectAltName=IP:127.0.0.1,DNS:localhost \
    -keyout "$work/server.key" -out "$work/server.crt" > "$work/certificate.log" 2>&1
cat > "$work/mosquitto.conf" <<EOF
per_listener_settings false
allow_anonymous false
password_file $work/passwords
acl_file $work/acl
persistence true
persistence_location $work/persistence/
autosave_interval 1
log_type all
listener $port 127.0.0.1
listener $tls_port 127.0.0.1
certfile $work/server.crt
keyfile $work/server.key
EOF
start()
{
    "$prefix/sbin/mosquitto" -c "$work/mosquitto.conf" > "$work/broker-$1.log" 2>&1 &
    broker_pid=$!
    attempt=0
    until grep 'mosquitto version .* running' "$work/broker-$1.log" >/dev/null; do
        if ! kill -0 "$broker_pid" 2>/dev/null || [ "$attempt" -ge 10 ]; then
            cat "$work/broker-$1.log" >&2
            echo 'Owned broker did not start; no existing service was stopped.' >&2
            exit 1
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
}
stop()
{
    kill -TERM "$broker_pid"
    wait "$broker_pid"
    broker_pid=
}
start first
for protocol in mqttv311 mqttv5; do
    for qos in 0 1 2; do
        topic=ember/test/$protocol/qos$qos
        payload="sensor=$protocol;qos=$qos;temperature=21.5"
        "$prefix/bin/mosquitto_pub" -h 127.0.0.1 -p "$port" -V "$protocol" \
            -u operator -P fixture-operator -t "$topic" -m "$payload" -q "$qos" -r
        actual=$("$prefix/bin/mosquitto_sub" -h 127.0.0.1 -p "$port" -V "$protocol" \
            -u observer -P fixture-observer -t "$topic" -q "$qos" -C 1 -W 5)
        [ "$actual" = "$payload" ]
        pass "$protocol QoS$qos authenticated retained delivery"
    done
done
if "$prefix/bin/mosquitto_pub" -h 127.0.0.1 -p "$port" -V mqttv5 \
    -t ember/test/anonymous -m forbidden -q 1 > "$work/anonymous.log" 2>&1; then
    echo 'Anonymous access was accepted.' >&2; exit 1
fi
grep -Ei 'not authori[sz]ed|bad user name or password' "$work/anonymous.log" >/dev/null
pass 'anonymous client rejected'
if "$prefix/bin/mosquitto_pub" -h 127.0.0.1 -p "$port" -V mqttv5 \
    -u operator -P wrong-fixture -t ember/test/wrong -m forbidden -q 1 \
    > "$work/wrong-password.log" 2>&1; then
    echo 'Wrong password was accepted.' >&2; exit 1
fi
grep -Ei 'not authori[sz]ed|bad user name or password' "$work/wrong-password.log" >/dev/null
pass 'incorrect password rejected'
# Upstream mosquitto_pub may return zero for a negative MQTT5 PUBACK.
# Check the protocol rejection and absence of retained data, not exit status alone.
"$prefix/bin/mosquitto_pub" -h 127.0.0.1 -p "$port" -V mqttv5 \
    -u observer -P fixture-observer -t ember/test/acl -m forbidden -q 1 -r \
    > "$work/acl-denied.log" 2>&1 || :
grep -Ei 'not authori[sz]ed' "$work/acl-denied.log" >/dev/null
result=0
"$prefix/bin/mosquitto_sub" -h 127.0.0.1 -p "$port" -V mqttv5 \
    -u operator -P fixture-operator -t ember/test/acl -C 1 -W 2 \
    > "$work/acl-retained.txt" 2> "$work/acl-retained.log" || result=$?
[ "$result" -eq 27 ] && [ ! -s "$work/acl-retained.txt" ]
pass 'read-only ACL rejects publication'
"$prefix/bin/mosquitto_pub" -h 127.0.0.1 -p "$tls_port" --cafile "$work/server.crt" \
    -V mqttv5 -u operator -P fixture-operator -t ember/test/tls -m encrypted -q 1 -r
actual=$("$prefix/bin/mosquitto_sub" -h 127.0.0.1 -p "$tls_port" --cafile "$work/server.crt" \
    -V mqttv5 -u observer -P fixture-observer -t ember/test/tls -C 1 -W 5)
[ "$actual" = encrypted ]
pass 'verified TLS MQTT round trip'
stop
[ -s "$work/persistence/mosquitto.db" ]
start second
actual=$("$prefix/bin/mosquitto_sub" -h 127.0.0.1 -p "$port" -V mqttv5 \
    -u observer -P fixture-observer -t ember/test/tls -C 1 -W 5)
[ "$actual" = encrypted ]
pass 'retained state survives broker restart'
stop
pass 'second clean shutdown'
ldd "$prefix/sbin/mosquitto" > "$work/broker-libraries.txt"
ldd "$prefix/lib/libmosquittopp.so" > "$work/cpp-libraries.txt"
echo "Installed MQTT checks complete: $work/results.txt"
