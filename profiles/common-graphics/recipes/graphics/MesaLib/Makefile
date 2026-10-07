# $NetBSD: Makefile,v 1.220 2026/04/06 10:47:10 wiz Exp $
# Origin: EmberBSD; AI-assisted bounded NetBSD 11/AArch64 source candidate.
DISTNAME=	mesa-26.2.4
PKGNAME=	${DISTNAME:S/mesa/MesaLib/}
PKGREVISION=	1
CATEGORIES=	graphics
MASTER_SITES=	https://archive.mesa3d.org/
EXTRACT_SUFX=	.tar.xz
MAINTAINER=	pkgsrc-users@NetBSD.org
HOMEPAGE=	https://www.mesa3d.org/
COMMENT=	Open source OpenGL implementation with VirGL and software rendering
LICENSE=	mit
CONFLICTS+=	libglapi-[0-9]* libglvnd-[0-9]*
ONLY_FOR_PLATFORM=	NetBSD-11.*-aarch64
USE_TOOLS+=	bison flex pkg-config xgettext
USE_LANGUAGES=	c c++
USE_CC_FEATURES+=	c11
USE_CXX_FEATURES+=	c++17
GCC_REQD+=	16.2
MESON_REQD+=	1.12.1
PYTHON_FOR_BUILD_ONLY=	tool
PYTHON_VERSION_REQD=	314
.include "../../mk/bsd.prefs.mk"
.include "../../lang/python/pyversion.mk"
.include "features.mk"
.include "options.mk"
.if !defined(EMBERBSD_COMMON_GRAPHICS)
PKG_FAIL_REASON+= "Mesa requires the prepared common graphics profile"
.endif
.if ${DISTNAME} != "mesa-26.2.4" || ${PKGREVISION} != "1"
PKG_FAIL_REASON+= "The common graphics profile requires adapted MesaLib 26.2.4nb1"
.endif
TOOL_DEPENDS+=	${PYPKGPREFIX}-mako-[0-9]*:../../devel/py-mako
TOOL_DEPENDS+=	${PYPKGPREFIX}-packaging-[0-9]*:../../devel/py-packaging
TOOL_DEPENDS+=	${PYPKGPREFIX}-yaml-[0-9]*:../../textproc/py-yaml
SUBST_CLASSES+=	python
SUBST_STAGE.python=	pre-configure
SUBST_FILES.python=	meson.build
SUBST_VARS.python=	PYTHONBIN
MESON_ARGS+=	-Dgallium-drivers=virgl,softpipe,llvmpipe
MESON_ARGS+=	-Dplatforms=x11,wayland -Dglx=dri
MESON_ARGS+=	-Degl=enabled -Dgbm=enabled -Dglvnd=disabled
MESON_ARGS+=	-Dgles1=enabled -Dgles2=enabled -Dopengl=true
MESON_ARGS+=	-Dllvm=enabled -Dshared-llvm=enabled -Dllvm-orcjit=true
MESON_ARGS+=	-Dvulkan-drivers= -Dvulkan-layers= -Dtools=
MESON_ARGS+=	-Dgallium-va=disabled -Dgallium-mediafoundation=disabled
MESON_ARGS+=	-Dgallium-rusticl=false -Dteflon=false -Dperfetto=false
MESON_ARGS+=	-Dspirv-tools=disabled -Dmicrosoft-clc=disabled -Dallow-fallback-for=
MESON_ARGS+=	-Dzlib=enabled -Dzstd=enabled -Ddisplay-info=disabled
MESON_ARGS+=	-Dlibunwind=disabled -Dvalgrind=disabled
MESON_ARGS+=	-Dbuild-tests=true -Dbuildtype=release -Db_lto=false
PKGCONFIG_OVERRIDE_STAGE=	pre-install
.for pc in gl glx egl gbm glesv1_cm glesv2 dri
PKGCONFIG_OVERRIDE+=	output/meson-private/${pc}.pc
.endfor
.include "../../lang/llvm/buildlink3.mk"
# The explicit absolute binary prevents Meson's default tool/CMake search.
MESON_BINARIES+=	llvm-config
MESON_BINARY.llvm-config=	${LLVM_CONFIG_PATH}
pre-configure:
	${TEST} -x ${PYTHONBIN:Q}
	${PYTHONBIN} -c 'import sys, mako, packaging, yaml; assert sys.version_info[:2] == (3, 14)'
	${TEST} -x ${LLVM_CONFIG_PATH:Q}
	${TEST} "$$(${LLVM_CONFIG_PATH} --version)" = 23.1.2
	${TEST} "$$(${LLVM_CONFIG_PATH} --shared-mode --link-shared)" = shared
	${TEST} "$$(${LLVM_CONFIG_PATH} --has-rtti)" = YES
	${LLVM_CONFIG_PATH} --link-shared --libs core executionengine orcjit native > /dev/null
.include "../../x11/libdrm/buildlink3.mk"
.include "../../archivers/zstd/buildlink3.mk"
.include "../../devel/zlib/buildlink3.mk"
.include "../../textproc/expat/buildlink3.mk"
.include "../../devel/libudev-bsd/buildlink3.mk"
.include "../../devel/wayland/buildlink3.mk"
BUILDLINK_API_DEPENDS.wayland-protocols+= wayland-protocols>=1.41
.include "../../devel/wayland-protocols/buildlink3.mk"
BUILDLINK_API_DEPENDS.libX11+= libX11>=1.6
.include "../../x11/libX11/buildlink3.mk"
.include "../../x11/libXext/buildlink3.mk"
.include "../../x11/libXrandr/buildlink3.mk"
.include "../../x11/libXxf86vm/buildlink3.mk"
BUILDLINK_API_DEPENDS.libxcb+= libxcb>=1.13
.include "../../x11/libxcb/buildlink3.mk"
BUILDLINK_API_DEPENDS.libxshmfence+= libxshmfence>=1.1
.include "../../x11/libxshmfence/buildlink3.mk"
.include "../../x11/xorgproto/buildlink3.mk"
.include "../../x11/xcb-proto/buildlink3.mk"
.include "../../lang/python/tool.mk"
.include "../../devel/meson/build.mk"
.include "../../mk/pthread.buildlink3.mk"
.include "../../mk/atomic64.mk"
.include "../../mk/bsd.pkg.mk"
