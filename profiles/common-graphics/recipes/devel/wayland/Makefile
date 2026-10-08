# $NetBSD: Makefile,v 1.35 2026/03/26 08:53:11 wiz Exp $
# Origin: EmberBSD (AI-assisted), current Wayland with a matching host scanner.

DISTNAME=	wayland-1.26.0
PKGREVISION=	1
CATEGORIES=	devel
MASTER_SITES=	https://gitlab.freedesktop.org/wayland/wayland/-/releases/${PKGVERSION_NOREV}/downloads/
EXTRACT_SUFX=	.tar.xz

MAINTAINER=	pkgsrc-users@NetBSD.org
HOMEPAGE=	https://wayland.freedesktop.org/
COMMENT=	Display server protocol - development libraries
LICENSE=	mit

# Documentation is disabled; the scanner validates DTDs through libxml2.

USE_TOOLS+=	pkg-config

USE_LANGUAGES=	c c++

MESON_ARGS+=	-Ddocumentation=false
MESON_ARGS+=	-Dtests=true

CFLAGS.NetBSD+=	-D_NETBSD_SOURCE

PKGCONFIG_OVERRIDE_STAGE=	pre-install
PKGCONFIG_OVERRIDE+=		output/meson-private/wayland-client.pc
PKGCONFIG_OVERRIDE+=		output/meson-private/wayland-cursor.pc
PKGCONFIG_OVERRIDE+=		output/meson-private/wayland-egl-backend.pc
PKGCONFIG_OVERRIDE+=		output/meson-private/wayland-egl.pc
PKGCONFIG_OVERRIDE+=		output/meson-private/wayland-scanner.pc
PKGCONFIG_OVERRIDE+=		output/meson-private/wayland-server.pc

.include "../../mk/bsd.fast.prefs.mk"

.if ${OPSYS} == "NetBSD" && ${OPSYS_VERSION} < 100000
CFLAGS.NetBSD+=	-Dppoll=pollts
.endif

.if ${USE_CROSS_COMPILE:tl} == "yes"
# wayland runs wayland-scanner at build-time.
.if defined(EMBERBSD_WAYLAND_SCANNER)
.include "cross-scanner.mk"
MESON_ARGS+=	-Dcross_scanner=${EMBERBSD_WAYLAND_SCANNER:Q}
.else
TOOL_DEPENDS+=	${PKGNAME}:../../${PKGPATH}
MESON_ARGS+=	-Dcross_scanner=${TOOLBASE:Q}/bin/wayland-scanner
.endif
.endif

.include "platform.mk"
.include "../../devel/meson/build.mk"
.if ${OPSYS} != "Linux"
.  include "../../devel/libepoll-shim/buildlink3.mk"
CPPFLAGS+=	-I${BUILDLINK_PREFIX.libepoll-shim}/include/libepoll-shim
.endif
.include "../../devel/libffi/buildlink3.mk"
.include "../../textproc/expat/buildlink3.mk"
.include "../../textproc/libxml2/buildlink3.mk"
.include "../../mk/bsd.pkg.mk"
