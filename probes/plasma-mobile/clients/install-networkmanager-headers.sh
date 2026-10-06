#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# AI-assisted EmberBSD portability probe; installs genuine upstream API headers.
set -eu
src=${1:?Usage: install-networkmanager-headers.sh source-directory prefix}
prefix=${2:?Usage: install-networkmanager-headers.sh source-directory prefix}
export PATH=/usr/pkg/bin:/usr/bin:/bin
include="$prefix/include/libnm"
mkdir -p "$include" "$prefix/lib/pkgconfig" "$prefix/share/licenses/networkmanager-headers"
cp "$src"/src/libnm-core-public/*.h "$src"/src/libnm-client-public/*.h "$include/"
sed -e 's/@NM_MAJOR_VERSION@/1/g' -e 's/@NM_MINOR_VERSION@/54/g' -e 's/@NM_MICRO_VERSION@/3/g' \
 "$src/src/libnm-core-public/nm-version-macros.h.in" > "$include/nm-version-macros.h"
# Use GLib's upstream enum generator, as the original Meson build does.
glib-mkenums --identifier-prefix NM \
 --fhead '#pragma once\n#include <glib-object.h>\nG_BEGIN_DECLS' \
 --vhead 'GType @enum_name@_get_type (void) G_GNUC_CONST;\n#define @ENUMPREFIX@_TYPE_@ENUMSHORT@ (@enum_name@_get_type ())' \
 --ftail 'G_END_DECLS' \
 "$src"/src/libnm-core-public/*.h "$include/nm-version-macros.h" > "$include/nm-core-enum-types.h"
glib-mkenums --identifier-prefix NM \
 --template "$src/src/libnm-client-public/nm-enum-types.h.template" \
 "$src"/src/libnm-client-public/*.h > "$include/nm-enum-types.h"
cp "$src"/COPYING* "$prefix/share/licenses/networkmanager-headers/"
cat > "$prefix/lib/pkgconfig/networkmanager-headers.pc" <<PC
prefix=$prefix
includedir=\${prefix}/include

Name: networkmanager-headers
Description: Original NetworkManager 1.54.3 public API headers; no libnm implementation
Version: 1.54.3
Requires.private: gio-2.0
Cflags: -DNM_NO_INCLUDE_EXTRA_HEADERS=1 -I\${includedir} -I\${includedir}/libnm
PC
