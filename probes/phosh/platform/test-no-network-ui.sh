#!/bin/sh
# Validate transformed templates and build their actual GResource bundle.
set -eu
umask 077
[ "$#" -eq 1 ] || { echo 'Usage: sh test-no-network-ui.sh PATCHED_PHOSH_SOURCE' >&2; exit 2; }
source_dir=$(CDPATH= cd "$1" && pwd)
for tool in xsltproc xmllint glib-compile-resources; do
    command -v "$tool" >/dev/null
done
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/phosh-network-ui-test.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
for ui in quick-settings top-panel; do
    output="$build_dir/$ui-no-network.ui"
    xsltproc --nonet -o "$output" "$source_dir/src/ui/no-network.xsl" "$source_dir/src/ui/$ui.ui"
    xmllint --noout "$output"
    count=$(xmllint --xpath 'count(//object[starts-with(@class,"PhoshWifi") or @class="PhoshWWanInfo" or @class="PhoshVpnInfo" or @class="PhoshConnectivityInfo"])' "$output")
    [ "$count" = 0 ] || { echo "Network widgets remain in $ui" >&2; exit 1; }
    if grep -E 'bind-source="(wifiinfo|wwaninfo|vpninfo|vpn_info|connectivity_info)"|on_(wifi|wwan|vpn)_clicked' "$output"; then
        echo "Network callbacks or bindings remain in $ui" >&2
        exit 1
    fi
done
# Ensure that removing network controls did not remove their containers.
[ "$(xmllint --xpath 'count(//*[@id="box"])' "$build_dir/quick-settings-no-network.ui")" = 1 ]
[ "$(xmllint --xpath 'count(//*[@id="settings"] | //*[@id="lbl_clock"] | //*[@id="status_icons_box"])' "$build_dir/top-panel-no-network.ui")" = 3 ]
xsltproc --nonet -o "$build_dir/phosh-no-network.gresources.xml" \
    "$source_dir/src/ui/no-network.xsl" "$source_dir/src/phosh.gresources.xml"
glib-compile-resources --sourcedir="$build_dir" --sourcedir="$source_dir/src" \
    --target="$build_dir/phosh.gresource" "$build_dir/phosh-no-network.gresources.xml"
echo 'Network widgets are excluded; both templates and the resource bundle validate.'
