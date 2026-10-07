#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted source-extracted EGL header ownership regression.
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 QTBASE_MAKEFILE NEW_WORK" >&2; exit 2; }
mkdir "$2"
work=$(CDPATH= cd -- "$2" && pwd)
mkdir -p "$work/base/include/EGL" "$work/package/include/EGL"
# Execute the actual candidate's PLIST block, retaining both header branches.
awk '/^\.  if !empty\(MESALIB_SUPPORTS_EGL:Myes\)/ {on=1} on {print} on && /^\.  endif/ {exit}' "$1" > "$work/selection.mk"
cat > "$work/Makefile" <<'MK'
MESALIB_SUPPORTS_EGL=yes
EMBERBSD_COMMON_GRAPHICS=yes
.include "selection.mk"
all:
	@printf '%s\n' '${PLIST.egldevice:U}'
MK
make=${BMAKE:-bmake}
choose_header() { (cd "$work" && "$make" -r -m / X11BASE="$work/base" BUILDLINK_PREFIX.MesaLib="$work/package"); }
printf '#define EGL_DRM_MASTER_FD_EXT 0x333C\n' > "$work/package/include/EGL/eglext.h"
printf 'stale base header without extension\n' > "$work/base/include/EGL/eglext.h"
[ "$(choose_header)" = yes ]
printf 'canonical package header without extension\n' > "$work/package/include/EGL/eglext.h"
printf '#define EGL_DRM_MASTER_FD_EXT 0x333C\n' > "$work/base/include/EGL/eglext.h"
[ -z "$(choose_header)" ]
echo 'PASS: Qtbase EGL PLIST follows the candidate package header despite contradictory base headers'
