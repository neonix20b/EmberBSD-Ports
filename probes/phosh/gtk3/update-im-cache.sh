#!/bin/sh
# GTK's Meson post-install updates GIO caches, not the GTK3 input-method cache.
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: sh update-im-cache.sh GTK3_PREFIX' >&2; exit 2; }
prefix=$1
case "$prefix" in /*) ;; *) echo 'Use an absolute GTK3 prefix.' >&2; exit 2 ;; esac
cache=$prefix/lib/gtk-3.0/3.0.0/immodules.cache
tmp=$(mktemp "$cache.XXXXXX")
trap 'rm -f "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
export LD_LIBRARY_PATH
"$prefix/bin/gtk-query-immodules-3.0" > "$tmp"
grep -q '^"wayland" ' "$tmp" || { echo 'GTK3 Wayland input module is missing.' >&2; exit 1; }
chmod 644 "$tmp"
mv "$tmp" "$cache"
printf 'GTK3 Wayland input cache: %s\n' "$cache"
