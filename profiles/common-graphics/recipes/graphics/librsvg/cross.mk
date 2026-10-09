# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), native Rust tools and real target GType queries.
# Included only for cross builds. Rust's target ABI name remains unchanged.
RUST_TYPE= native
TOOL_DEPENDS+= rust-bin-1.99.0{,nb[0-9]*}:../../lang/rust-bin
TOOL_DEPENDS+= rust-std-aarch64-netbsd-1.99.0{,nb[0-9]*}:../../lang/rust-std-aarch64-netbsd
BUILD_DEPENDS+= glib2-introspection>=2.90.1nb1:../../devel/glib2-introspection

EMBERBSD_GI_MESON_OPTIONS= no
.include "../../devel/gobject-introspection/cross.mk"
BUILDLINK_API_DEPENDS.gobject-introspection+= gobject-introspection>=1.86.0nb5
MESON_ARGS+= -Dtriplet=aarch64-unknown-netbsd -Dintrospection=enabled
MESON_CROSS_VARS+= emberbsd_gi_cross emberbsd_gi_ldd_wrapper
MESON_CROSS.emberbsd_gi_cross= true
MESON_CROSS.emberbsd_gi_ldd_wrapper= '${EMBERBSD_GI_FILESDIR}/elf-needed.sh'
# pkg-config rebases lookup paths, but installation needs the target prefix.
MESON_CROSS_VARS+= emberbsd_pixbuf_module_dir
MESON_CROSS.emberbsd_pixbuf_module_dir= '${PREFIX}/lib/gdk-pixbuf-2.0/2.10.0/loaders'
# The symbol exporter and install step inspect target ELF, not Mach-O.
MESON_BINARIES+= nm strip
MESON_BINARY.nm= ${TOOLDIR}/bin/aarch64--netbsd-nm
MESON_BINARY.strip= ${TOOLDIR}/bin/aarch64--netbsd-strip
# The native scanner canonicalizes include paths. Map that sysroot spelling
# back into the declared buildlink tree instead of admitting host directories.
EMBERBSD_RSVG_REAL_SYSROOT!= cd ${CROSS_DESTDIR:Q} && pwd -P
BUILDLINK_TRANSFORM+= I:${EMBERBSD_RSVG_REAL_SYSROOT}${PREFIX}:${BUILDLINK_DIR}

# pkgsrc's native Rust mode avoids selecting a target compiler package.
# The declared host packages still own and validate these tools and target std.
TOOLS_CREATE+= cargo rustc cargo-cbuild
.for _rust_tool in cargo rustc cargo-cbuild
TOOLS_PATH.${_rust_tool}= ${TOOLBASE}/bin/${_rust_tool}
.endfor
MAKE_ENV+= RUSTC=${TOOLBASE}/bin/rustc
MAKE_ENV+= CARGO_NET_OFFLINE=true CARGO_BUILD_JOBS=${MAKE_JOBS:U1}
MAKE_ENV+= CARGO_TARGET_AARCH64_UNKNOWN_NETBSD_LINKER=${WRAPPER_BINDIR}/cc
MAKE_ENV+= CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER=${EMBERBSD_CROSS_BUILD_CC}
MAKE_ENV+= HOST_CC=${EMBERBSD_CROSS_BUILD_CC} HOST_CXX=${EMBERBSD_CROSS_BUILD_CXX}
MAKE_ENV+= HOST_AR=/usr/bin/ar
MAKE_ENV+= HOST_CFLAGS= HOST_CXXFLAGS=
MAKE_ENV+= CC_aarch64_unknown_netbsd=${WRAPPER_BINDIR}/cc
MAKE_ENV+= CXX_aarch64_unknown_netbsd=${WRAPPER_BINDIR}/c++
MAKE_ENV+= AR_aarch64_unknown_netbsd=${TOOLDIR}/bin/aarch64--netbsd-ar
MAKE_ENV+= PKG_CONFIG_ALLOW_CROSS=1
RUSTFLAGS+= -C link-arg=-Wl,-rpath,${PREFIX}/lib
# Panic locations must not retain private source/vendor paths in the package.
RUSTFLAGS+= --remap-path-prefix=${WRKDIR}=.

pre-configure: emberbsd-librsvg-rust
.PHONY: emberbsd-librsvg-rust
emberbsd-librsvg-rust:
	${RUN}${TOOLBASE}/bin/rustc --version | ${GREP} '^rustc 1\.99\.0 '
	${RUN}${TEST} -n "$$(${FIND} ${TOOLBASE}/lib/rustlib/aarch64-unknown-netbsd/lib -name 'libstd-*.rlib' -print)"
