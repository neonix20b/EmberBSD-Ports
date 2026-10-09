# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), native generators with real target GType queries.
.include "../../mk/bsd.prefs.mk"
.if ${USE_CROSS_COMPILE:Uno:tl} == "yes"
.if ${OPSYS} != "NetBSD" || ${MACHINE_ARCH} != "aarch64"
PKG_FAIL_REASON+= "The GI cross recipe is validated for NetBSD/AArch64"
.endif
.for _input in EMBERBSD_GI_RUBY EMBERBSD_GI_QUERY_CONFIG EMBERBSD_CROSS_BUILD_CC
.if empty(${_input}:M/*) || !empty(${_input}:C/[A-Za-z0-9_.\/-]//g) || !exists(${${_input}})
PKG_FAIL_REASON+= "${_input} must name an existing absolute file without shell metacharacters"
.endif
.endfor
# Cross dependency traversal builds the native tool package independently.
TOOL_DEPENDS+= gobject-introspection>=1.86.0nb4:../../devel/gobject-introspection
MESON_ARGS+= -Dgi_cross_use_prebuilt_gi=true
MESON_ARGS+= -Dgi_cross_ldd_wrapper=${FILESDIR}/elf-needed.sh
MAKE_ENV+= GI_CROSS_LAUNCHER=${EMBERBSD_GI_RUBY:Q}\ ${FILESDIR:Q}/target-query.rb
MAKE_ENV+= EMBERBSD_GI_QUERY_CONFIG=${EMBERBSD_GI_QUERY_CONFIG:Q}
MAKE_ENV+= EMBERBSD_GI_READELF=${TOOLDIR:Q}/bin/aarch64--netbsd-readelf
MESON_NATIVE_ARGS+= --native-file ${WRKDIR}/.meson-gi-native

pre-configure: emberbsd-gi-native
.PHONY: emberbsd-gi-native
emberbsd-gi-native:
	${RUN}${SETENV} EMBERBSD_GI_QUERY_CONFIG=${EMBERBSD_GI_QUERY_CONFIG:Q} ${EMBERBSD_GI_RUBY} ${FILESDIR}/target-query.rb --check ${WRKDIR} ${CROSS_DESTDIR} ${TOOLDIR}/bin/aarch64--netbsd-readelf
	${RUN}${TEST} -x ${TOOLBASE}/bin/g-ir-scanner && ${TEST} -x ${TOOLBASE}/bin/g-ir-compiler
	${RUN}version=$$(env PKG_CONFIG_SYSROOT_DIR= PKG_CONFIG_PATH= PKG_CONFIG_LIBDIR=${TOOLBASE}/lib/pkgconfig:${TOOLBASE}/share/pkgconfig ${TOOLBASE}/bin/pkg-config --modversion gobject-introspection-1.0); ${TEST} "$$version" = 1.86.0
	${RUN}${PRINTF} '%s\n' '[binaries]' \
	    "c = '${EMBERBSD_CROSS_BUILD_CC}'" \
	    "g-ir-scanner = '${TOOLBASE}/bin/g-ir-scanner'" \
	    "g-ir-compiler = '${TOOLBASE}/bin/g-ir-compiler'" \
	    "pkg-config = ['/usr/bin/env', 'PKG_CONFIG_SYSROOT_DIR=', '${TOOLBASE}/bin/pkg-config']" \
	    '[properties]' \
	    "pkg_config_libdir = ['${TOOLBASE}/lib/pkgconfig', '${TOOLBASE}/share/pkgconfig']" \
	    '[built-in options]' 'pkg_config_path = []' > ${WRKDIR}/.meson-gi-native
.endif
