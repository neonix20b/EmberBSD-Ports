#!/bin/sh
# Match the native gettext ABI used by NetBSD's installed GLib and GTK.
# pkgsrc buildlink normally selects it; direct Meson builds need the same choice.
set -eu
result=$(/usr/pkg/bin/pkg-config "$@") || exit $?
printf '%s\n' "$result" | sed -E 's#(^|[[:space:]])-lintl([[:space:]]|$)#\1/usr/lib/libintl.so.1\2#g'
