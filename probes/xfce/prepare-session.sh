#!/bin/sh
# Prepare supported Xfce configuration for an isolated X11 session.
set -eu
umask 077
[ "$#" = 2 ] || { echo 'Usage: sh prepare-session.sh PREFIX PRIVATE_XDG_CONFIG_HOME' >&2; exit 2; }
prefix=$1
config=$2
for path in "$prefix" "$config"; do
    case "$path" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./-]*) echo 'Use simple paths.' >&2; exit 2 ;; esac
done
[ -x "$prefix/bin/xfce4-session" ] || { echo 'Build xfce4-session first.' >&2; exit 2; }
[ -x /usr/bin/false ] || { echo 'The explicit failing lock command is unavailable.' >&2; exit 2; }
session=$prefix/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml
panel=$prefix/etc/xdg/xfce4/panel/default.xml
keys=$prefix/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml
for file in "$session" "$panel" "$keys"; do
    [ -f "$file" ] || { echo "Missing installed default: $file" >&2; exit 2; }
done
[ ! -e "$config/xfce4" ] || { echo 'Use a fresh private XDG configuration directory.' >&2; exit 2; }
channel=$config/xfce4/xfconf/xfce-perchannel-xml
mkdir -p "$channel" "$config/autostart"
# Kiosk is read from libxfce4util's compiled sysconfdir, not the user XDG dir.
mkdir -p "$prefix/etc/xdg/xfce4/kiosk"
cat > "$prefix/etc/xdg/xfce4/kiosk/kioskrc" <<'EOF'
[xfce4-session]
Shutdown=NONE
SaveSession=NONE
CustomizeLogout=NONE
CustomizeCompatibility=NONE
CustomizeSecurity=NONE
EOF
awk '
    /name="LockCommand"/ { sub(/value=""/, "value=\"/usr/bin/false\"") }
    /value="Thunar"/ { sub(/value="Thunar"/, "value=\"thunar\"") }
    /name="general"/ {
        print
        print "    <property name=\"SaveOnExit\" type=\"bool\" value=\"false\"/>"
        print "    <property name=\"StartAssistiveTechnologies\" type=\"bool\" value=\"false\"/>"
        next
    }
    /<\/channel>/ {
        print "  <property name=\"compat\" type=\"empty\">"
        print "    <property name=\"LaunchGNOME\" type=\"bool\" value=\"false\"/>"
        print "    <property name=\"LaunchKDE\" type=\"bool\" value=\"false\"/>"
        print "  </property>"
        print "  <property name=\"startup\" type=\"empty\">"
        print "    <property name=\"gpg-agent\" type=\"empty\"><property name=\"enabled\" type=\"bool\" value=\"false\"/></property>"
        print "    <property name=\"ssh-agent\" type=\"empty\"><property name=\"enabled\" type=\"bool\" value=\"false\"/></property>"
        print "  </property>"
        print "  <property name=\"shutdown\" type=\"empty\">"
        print "    <property name=\"LockScreen\" type=\"bool\" value=\"true\"/>"
        print "    <property name=\"ShowSuspend\" type=\"bool\" value=\"false\"/>"
        print "    <property name=\"ShowHibernate\" type=\"bool\" value=\"false\"/>"
        print "    <property name=\"ShowHybridSleep\" type=\"bool\" value=\"false\"/>"
        print "    <property name=\"ShowSwitchUser\" type=\"bool\" value=\"false\"/>"
        print "  </property>"
    }
    { print }
' "$session" > "$channel/xfce4-session.xml"
awk '
    /value="actions"\/>/ {
        sub(/\/>/, ">")
        print
        print "      <property name=\"items\" type=\"array\"><value type=\"string\" value=\"+logout\"/></property>"
        print "    </property>"
        next
    }
    { print }
' "$panel" > "$channel/xfce4-panel.xml"
# Xfconf merges system defaults; an omitted property would keep the binding.
sed 's/value="xflock4"/value=""/' "$keys" > "$channel/xfce4-keyboard-shortcuts.xml"
# xfsettingsd is already one of the explicit failsafe clients.
cat > "$config/autostart/xfsettingsd.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Xfce settings daemon
Hidden=true
EOF
printf 'Prepared %s. Use only %s/etc/xdg in XDG_CONFIG_DIRS.\n' "$config" "$prefix"
