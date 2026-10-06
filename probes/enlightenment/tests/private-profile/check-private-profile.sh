#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: check-private-profile.sh PATCHED_SOURCE' >&2; exit 2; }
src=$(cd "$1" && pwd)
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/enlightenment-private-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

# Upstream puts the complete return type on the line before each function.
# Extract complete definitions, failing if a function is missing or duplicated.
extract()
{
    awk -v symbol="$2" '
    $0 ~ "^" symbol "\\(" {
        if (found++) exit 2
        print previous
        active = 1
    }
    active {
        print
        line = $0
        opened += gsub(/\{/, "{", line)
        closed += gsub(/\}/, "}", line)
        if (opened && opened == closed) active = 0
    }
    { previous = $0 }
    END { if (found != 1 || active) exit 1 }
    ' "$1" >> "$tmp/actual-functions.inc"
}
extract "$src/src/bin/e_system.c" e_system_services_enabled_get
for name in _e_sys_action_allowed e_sys_action_possible_get e_sys_action_do e_sys_action_raw_do; do
    extract "$src/src/bin/e_sys.c" "$name"
done
extract "$src/src/bin/e_desklock.c" e_desklock_show
extract "$src/src/bin/e_backlight.c" _backlight_devices_probe
for enabled in 0 1; do
    "${CC:-cc}" -std=c99 -Wall -Wextra -Werror -DE_SYSTEM_SERVICES="$enabled" \
        -I "$src/src/bin" -I "$tmp" "$test_dir/test-system-services.c" \
        -o "$tmp/policy-$enabled"
    "$tmp/policy-$enabled"
done

filter="$src/data/config/standard/private-profile.sh"
sh -n "$filter"
for config in e e_bindings; do
    sh "$filter" "$src/data/config/standard/$config.src" "$tmp/$config.src"
    sh "$filter" "$tmp/$config.src" "$tmp/$config.again.src"
    cmp "$tmp/$config.src" "$tmp/$config.again.src"
    awk '
    { line=$0; depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line) }
    depth < 0 { exit 1 }
    END { if (depth != 0) exit 1 }
    ' "$tmp/$config.src"
done
awk '
/value "name" string: "(backlight|battery|bluez5|connman|cpufreq|geolocation|lokker|mixer|packagekit|polkit|temperature)"/ { exit 1 }
/value "(desklock_start_locked|desklock_on_suspend|desklock_autolock_screensaver|screensaver_enable|screensaver_suspend|screensaver_suspend_on_ac|dpms_enable|dpms_standby_enable|dpms_suspend_enable|dpms_off_enable|backlight\.idle_dim|backlight\.ddc)"/ {
    if ($0 !~ /: 0;/) exit 1
    settings++
}
/value "name" string: "(clock|pager|ibar|ibox|start|syscon|everything)"/ { stock++ }
END { if (settings < 10 || stock < 7) exit 1 }
' "$tmp/e.src"
for config in e e_bindings; do
    if grep -Eq 'value "action" string: "(desk_lock|halt|halt_now|reboot|suspend|suspend_smart|hibernate|backlight|backlight_adjust|volume_decrease|volume_increase|volume_mute)"' "$tmp/$config.src"; then
        echo "Unavailable action retained in $config" >&2
        exit 1
    fi
done
grep 'value "config_version"' "$src/data/config/standard/e.src" > "$tmp/version-stock"
grep 'value "config_version"' "$tmp/e.src" > "$tmp/version-private"
cmp "$tmp/version-stock" "$tmp/version-private"
grep -q 'value "action" string: "logout"' "$tmp/e.src"
grep -q 'value "action" string: "window_fullscreen_toggle"' "$tmp/e_bindings.src"
echo 'PASS: private standard profile retains desktop actions and disables hardware/lock/idle'
