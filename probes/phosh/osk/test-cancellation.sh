#!/bin/sh
# Check test.sh supervision with real Xvfb/D-Bus and a controlled Meson fixture.
set -eu
umask 077
ulimit -c 0
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
    echo 'Usage: sh test-cancellation.sh BUILD_DIRECTORY [TEST_HELPER]' >&2
    exit 2
}
work=$1
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
helper=${2:-$recipe/test.sh}
PATH=/usr/pkg/bin:/usr/X11R7/bin:/usr/bin:/bin
export PATH
case "$work:$helper" in /*:/*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
log=$(mktemp -d "$work/cancellation.XXXXXXXX")
runner=
cleanup()
{
    trap - EXIT
    trap '' HUP INT TERM
    # This driver owns every recorded process and process group.
    for signal in TERM KILL; do
        for pid in "$runner" $(cat "$log"/*/*.pid 2>/dev/null || true); do
            case "$pid" in ''|*[!0-9]*) continue ;; esac
            kill -s "$signal" "$pid" 2>/dev/null || true
            kill -s "$signal" -- "-$pid" 2>/dev/null || true
        done
        [ "$signal" != TERM ] || sleep 1
    done
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
# A background shell inherits ignored SIGINT. Restore foreground semantics
# so sending INT directly to the test helper exercises its actual trap.
cat > "$log/start.c" <<'C'
#include <sys/types.h>
#include <unistd.h>
#include <signal.h>
#include <stdio.h>
int
main(int argc, char **argv)
{
    if (argc < 2)
        return 2;
    signal(SIGINT, SIG_DFL);
    signal(SIGHUP, SIG_DFL);
    signal(SIGTERM, SIG_DFL);
    if (setsid() == -1) {
        perror("setsid");
        return 1;
    }
    execvp(argv[1], argv + 1);
    perror(argv[1]);
    return 127;
}
C
cc -o "$log/start" "$log/start.c"
for mode in success failure TERM HUP INT; do
    fixture=$log/$mode
    mkdir "$fixture" "$fixture/tools" "$fixture/logs" "$fixture/install" "$fixture/install/bin"
    cp "$work/support-prefix.txt" "$work/phoc-prefix.txt" "$fixture/"
    ln -s "$work/install/bin/phosh-osk-stevia" "$fixture/install/bin/phosh-osk-stevia"
    cat > "$fixture/tools/meson" <<'MESON'
#!/bin/sh
set -eu
printf '%s\n' "$$" > "$FIXTURE/meson.pid"
ps -o ppid= -p "$$" | tr -d ' ' > "$FIXTURE/bus-runner.pid"
gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.GetConnectionUnixProcessID org.freedesktop.DBus |
    sed -n 's/^(uint32 \([0-9][0-9]*\),)$/\1/p' > "$FIXTURE/bus.pid"
test_parent=$(ps -o ppid= -p "$(cat "$FIXTURE/bus-runner.pid")" | tr -d ' ')
pgrep -P "$test_parent" -x Xvfb > "$FIXTURE/xvfb.pid"
case "$MODE" in
    success) exit 0 ;;
    failure) exit 17 ;;
esac
# Neither a stopped X server nor a stopped grandchild can process SIGTERM.
# Cleanup must reach its SIGKILL deadline and collect the whole subtree.
sleep 300 &
child=$!
printf '%s\n' "$child" > "$FIXTURE/grandchild.pid"
kill -STOP "$child" "$(cat "$FIXTURE/xvfb.pid")"
printf '%s\n' ready > "$FIXTURE/ready"
wait "$child"
MESON
    chmod 700 "$fixture/tools/meson"
    FIXTURE=$fixture MODE=$mode "$log/start" sh "$helper" "$fixture" > "$fixture/helper.log" 2>&1 &
    runner=$!
    case "$mode" in
        success) expected=0 ;;
        failure) expected=17 ;;
        *)
            i=0
            while [ ! -s "$fixture/ready" ]; do
                kill -0 "$runner" || { cat "$fixture/helper.log" >&2; exit 1; }
                i=$((i + 1))
                [ "$i" -lt 10 ] || { echo "$mode: fixture startup timed out" >&2; exit 1; }
                sleep 1
            done
            kill -s "$mode" "$runner"
            case "$mode" in TERM) expected=143 ;; HUP) expected=129 ;; INT) expected=130 ;; esac
            ;;
    esac
    i=0
    while kill -0 "$runner" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -lt 10 ] || { echo "$mode: helper ignored cancellation or cleanup hung" >&2; exit 1; }
        sleep 1
    done
    status=0
    wait "$runner" || status=$?
    runner=
    [ "$status" -eq "$expected" ] || {
        cat "$fixture/helper.log" >&2
        echo "$mode: expected $expected, got $status" >&2
        exit 1
    }
    for file in "$fixture"/*.pid; do
        pid=$(cat "$file")
        case "$pid" in ''|*[!0-9]*) echo "Invalid fixture PID: $file" >&2; exit 1 ;; esac
        if kill -0 "$pid" 2>/dev/null; then
            echo "$mode: process survived cleanup: $pid ($file)" >&2
            exit 1
        fi
    done
    for file in "$fixture"/*.pid; do mv "$file" "$file.checked"; done
    printf '%s: exit %s; private Xvfb, D-Bus, runner and test subtree stopped\n' "$mode" "$status"
done
printf 'Cancellation regression passed. Logs: %s\n' "$log"
