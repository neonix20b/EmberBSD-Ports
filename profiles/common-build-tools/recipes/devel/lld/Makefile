# $NetBSD: Makefile,v 1.28 2026/03/25 22:56:24 wiz Exp $

.include "../../lang/llvm/version.mk"

PKGNAME=	lld-${LLVM_VERSION}
CATEGORIES=	devel

MAINTAINER=	pkgsrc-users@NetBSD.org
HOMEPAGE=	https://lld.llvm.org/
COMMENT=	The LLVM Linker
LICENSE=	apache-2.0

USE_CXX_FEATURES=	c++17
USE_LANGUAGES=		c c++
GCC_REQD+=		16.2

CMAKE_CONFIGURE_ARGS+=	-DCMAKE_BUILD_TYPE=Release
CMAKE_CONFIGURE_ARGS+=	-DCMAKE_C_COMPILER=${CC:Q}
CMAKE_CONFIGURE_ARGS+=	-DCMAKE_CXX_COMPILER=${CXX:Q}

PYTHON_FOR_BUILD_ONLY=	yes

INSTALLATION_DIRS+=	libexec/lld

post-install:
	${LN} -sf ${PREFIX}/bin/lld ${DESTDIR}${PREFIX}/libexec/lld/ld

.include "options.mk"
.include "../../devel/cmake/build.mk"
.include "../../lang/llvm/buildlink3.mk"
.include "../../devel/py-llvm-lit/buildlink3.mk"
CMAKE_CONFIGURE_ARGS+=	-DLLVM_DIR=${BUILDLINK_PREFIX.llvm:Q}/lib/cmake/llvm
CMAKE_CONFIGURE_ARGS+=	-DLLVM_CMAKE_DIR=${BUILDLINK_PREFIX.llvm:Q}/lib/cmake/llvm
CMAKE_CONFIGURE_ARGS+=	-DPython3_EXECUTABLE=${PYTHONBIN:Q}
CMAKE_CONFIGURE_ARGS+=	-DLLVM_EXTERNAL_LIT=${BUILDLINK_PREFIX.py-llvm-lit:Q}/bin/llvm-lit
CMAKE_CONFIGURE_ARGS+=	-DLLVM_INSTALL_TOOLCHAIN_ONLY=OFF
.if !empty(PKG_OPTIONS:Mtests) && empty(PKG_BUILD_OPTIONS.llvm:Mtests)
PKG_FAIL_REASON+= "LLD tests require matching LLVM llvm_gtest exports (tests option)"
.endif
.include "../../lang/python/tool.mk"
.include "../../mk/atomic64.mk"
DEPENDS+= llvm-${LLVM_VERSION}{,nb*}:../../lang/llvm

pre-configure:
	${TEST} "`${LLVM_CONFIG_PATH} --version`" = "${LLVM_VERSION}"

.include "../../mk/bsd.pkg.mk"
