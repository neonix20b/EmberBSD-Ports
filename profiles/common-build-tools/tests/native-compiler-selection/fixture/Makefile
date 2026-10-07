DISTNAME= emberbsd-gcc16-selection-1.0
CATEGORIES= devel
COMMENT= Private actual pkgsrc compiler selection fixture
LICENSE= 2-clause-bsd
NO_CHECKSUM= yes
DISTFILES=

NO_CONFIGURE= yes
USE_LANGUAGES= c c++
INSTALLATION_DIRS= libexec/emberbsd-transition

do-extract:
	${MKDIR} ${WRKSRC}
	${CP} ${FILESDIR}/consumer.c ${FILESDIR}/consumer.cc ${WRKSRC}

do-build:
	cd ${WRKSRC} && ${CC} ${CFLAGS} ${LDFLAGS} -std=c11 consumer.c -o c-consumer
	cd ${WRKSRC} && ${CXX} ${CXXFLAGS} ${LDFLAGS} -std=c++20 consumer.cc -o cxx-consumer

do-install:
	${INSTALL_PROGRAM} ${WRKSRC}/c-consumer ${DESTDIR}${PREFIX}/libexec/emberbsd-transition/c-consumer
	${INSTALL_PROGRAM} ${WRKSRC}/cxx-consumer ${DESTDIR}${PREFIX}/libexec/emberbsd-transition/cxx-consumer

.include "../../mk/bsd.pkg.mk"
