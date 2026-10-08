#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), adapt GDB's bundled Libtool to cross RPATHs.
set -eu
[ "$#" = 2 ] || { echo "Usage: $0 GENERATED_LIBTOOL SYSROOT" >&2; exit 2; }
file=$1 sysroot=$2
case "$sysroot" in /*) ;; *) exit 2 ;; esac
case "$sysroot" in *[!A-Za-z0-9_./-]*|*/) exit 2 ;; esac
# Keep build-time -L paths. Only the inferred runtime directory loses the
# sysroot prefix; explicit target -Wl,-rpath options retain their meaning.
awk -v root="$sysroot" '
/^hardcode_libdir_flag_spec=/ {
    $0 = "hardcode_libdir_flag_spec=\"\\${wl}-rpath \\${wl}\\${libdir#" root "}\""
    count++
}
{ print }
END { if (count != 2) exit 1 }
' "$file" > "$file.ember-new"
chmod +x "$file.ember-new"
mv "$file.ember-new" "$file"
