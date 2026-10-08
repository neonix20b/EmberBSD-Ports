#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), installed desktop-support runtime guards.
set -eu
[ "$#" = 2 ] || { echo 'Usage: run-desktop-support.sh BUNDLE NEW_LOGS' >&2; exit 2; }
bundle=$(CDPATH= cd -- "$1" && pwd -P)
[ "$(uname -s)" = NetBSD ]
[ "$(uname -p)" = aarch64 ]
[ -z "${LD_LIBRARY_PATH-}${LD_PRELOAD-}${DBUS_SESSION_BUS_ADDRESS-}${DBUS_SYSTEM_BUS_ADDRESS-}" ]
sh "$bundle/run-mesa-package-tests.sh" --verify-sysroot "$bundle" /
umask 077
mkdir "$2"
logs=$(CDPATH= cd -- "$2" && pwd -P)
case "$logs" in *\&*|*\<*|*\>*|*\"*|*\'*) echo 'XML-unsafe log directory' >&2; exit 2;; esac
for program in "$bundle"/bin/sfdo-* /usr/pkg/bin/dbus-daemon /usr/pkg/bin/dbus-run-session \
    /usr/pkg/bin/dbus-send /usr/pkg/bin/dbus-test-tool; do
    ldd "$program" > "$logs/$(basename "$program").ldd" 2>&1
    awk '$2 == "=>" && $3 !~ /^\// {bad=1} END {exit bad}' "$logs/$(basename "$program").ldd"
    for library in $(awk '$2 == "=>" {print $3}' "$logs/$(basename "$program").ldd"); do
        case "$library" in
            /usr/pkg/*) awk -v p="$library" '$2 == p {found=1} END {exit !found}' "$bundle/runtime-libraries.sha256";;
            /usr/lib/*|/lib/*) ;;
            *) echo "Foreign provider: $library" >&2; exit 1;;
        esac
    done
done
# The upstream icon test changes cache mtimes; keep the sealed fixtures intact.
cp -R "$bundle/source/libsfdo/tests" "$logs/fixtures"
for name in basedir desktop-file desktop icon; do
    (cd "$logs/fixtures" && env -i PATH=/bin:/usr/bin HOME="$logs" \
        /usr/bin/timeout -k 5 15 "$bundle/bin/sfdo-$name") > "$logs/sfdo-$name.log" 2>&1 || {
        cat "$logs/sfdo-$name.log"; exit 1;
    }
    echo "PASS: installed libsfdo upstream $name test"
done
cat > "$logs/session.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:tmpdir=$logs</listen><auth>EXTERNAL</auth>
<policy context="default"><allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/></policy></busconfig>
EOF
env -i PATH=/bin:/usr/bin:/usr/pkg/bin HOME="$logs" \
    /usr/bin/timeout -k 5 30 /usr/pkg/bin/dbus-run-session --dbus-daemon=/usr/pkg/bin/dbus-daemon \
    --config-file="$logs/session.conf" -- /bin/sh "$bundle/desktop-session-bus.sh" "$logs" \
    > "$logs/session.log" 2>&1 || { cat "$logs/session.log"; exit 1; }
cat "$logs/session.log"
grep -Fxq 'PASS: session D-Bus ownership, eight empty replies, explicit errors and owner release' "$logs/session.log"
pid=$(cat "$logs/bus-pid")
case "$pid" in ''|*[!0-9]*) exit 1;; esac
[ "$pid" -gt 1 ]
# Upstream dbus-run-session sends SIGTERM without waitpid on this path.
# Observe bounded disappearance; never signal a PID we do not own here.
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.1
done
if kill -0 "$pid" 2>/dev/null; then echo 'Session daemon survived its wrapper' >&2; exit 1; fi
sh "$bundle/run-mesa-package-tests.sh" --verify-sysroot "$bundle" /
echo 'PASS: installed desktop support; session daemon terminated; package payload unchanged'
