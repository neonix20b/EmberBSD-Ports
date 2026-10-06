#!/bin/sh
# Check the generated Xfconf policy without starting a desktop session.
set -eu
[ "$#" = 1 ] || { echo 'Usage: sh check-session-profile.sh PRIVATE_XDG_CONFIG_HOME' >&2; exit 2; }
command -v xmllint >/dev/null || { echo 'xmllint is required.' >&2; exit 2; }
channel=$1/xfce4/xfconf/xfce-perchannel-xml
keys=$channel/xfce4-keyboard-shortcuts.xml
session=$channel/xfce4-session.xml
panel=$channel/xfce4-panel.xml
for file in "$keys" "$session" "$panel"; do
    [ -f "$file" ] || { echo "Missing profile: $file" >&2; exit 1; }
    xmllint --nonet --noout "$file"
done

check()
{
    file=$1
    expression=$2
    message=$3
    result=$(xmllint --nonet --xpath "boolean($expression)" "$file")
    [ "$result" = true ] || { echo "FAIL: $message" >&2; exit 1; }
}

# A missing user property would expose the installed system default again.
shortcut="/channel[@name='xfce4-keyboard-shortcuts']/property[@name='commands']/property[@name='default']/property[@name='<Primary><Alt>l']"
check "$keys" "count($shortcut) = 1 and $shortcut/@type = 'string' and $shortcut/@value = ''" \
    'The lock shortcut must have an explicit empty override.'

lock="/channel[@name='xfce4-session']/property[@name='general']/property[@name='LockCommand']"
check "$session" "count($lock) = 1 and $lock/@type = 'string' and $lock/@value = '/usr/bin/false'" \
    'The session lock command must be /usr/bin/false.'

actions="/channel[@name='xfce4-panel']/property[@name='plugins']/property[@value='actions']"
items="$actions/property[@name='items']"
check "$panel" "count($actions) = 1 and count($items) = 1 and $items/@type = 'array' and count($items/value) = 1 and $items/value/@type = 'string' and $items/value/@value = '+logout'" \
    'The panel actions plugin must contain only +logout.'

echo 'PASS: explicit empty lock shortcut, failing lock command and logout-only panel.'
