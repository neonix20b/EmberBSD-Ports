# Cross-packaged librsvg

The common graphics profile selects librsvg 2.63.2, including its C library,
`rsvg-convert`, the dynamic GdkPixbuf SVG loader and Rsvg GIR/typelib.
Embedded AVIF is enabled through dav1d 1.5.4. xxHash 0.8.4 supplies dav1d's
build dependency. [GdkPixbuf and shared MIME data](gdk-pixbuf.md),
[GLib metadata](introspection.md#glib-2901-metadata-package), and the
[native Rust toolchain with target std](../../common-build-tools/rust-target-std.md)
are prerequisites, not alternate dependency stacks.

## Current validation boundary

The full package builds on macOS and installs in the private EmberBSD cross
sysroot. All 14 installed files and symlinks match the package. Source checks
cover the unchanged Cargo.lock, all 357 crate archives and 31 patches. The
native/cross Meson selection and header-mapping regression pass. Rsvg GIR and
typelib generation used a successful real target GType query.

The first CM5 packaged consumer passed its C API SVG RGB pixels and CLI PNG
pixels, then failed `dynamic GdkPixbuf SVG loader` in the first cycle. Its
temporary directory was cleaned successfully. The test currently omits the
GError detail at that assertion, so the loader failure's cause is unresolved.
Embedded AVIF, text, typelib invocation and four complete lifecycles were not
reached and are not validated. The next diagnostic step is to print that
GError and repeat the loader check alone. The conditional AVIF/dav1d consumer
buildlink correction is saved; downstream labwc configure has not been rerun.

The exporter passed 98 refusal checks and one complete common-profile export
before the final loader-install patch. The additional refusal and final export
composition remain to be rerun. Full SVG runtime acceptance remains open.

Sources come from [GNOME](https://download.gnome.org/sources/librsvg/2.63/),
[VideoLAN](https://downloads.videolan.org/pub/videolan/dav1d/1.5.4/) and
[xxHash upstream](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4).
Their versions and SHA256 values are in [sources.tsv](../sources.tsv).
The original Cargo.lock remains unchanged. Its 357 registry archives have
matching SHA256 values, and pkgsrc verifies the separately recorded archive
digests before extraction. Cargo builds offline with `--locked`.

## Cross adaptation

The recipe uses pkgsrc's `RUST_TYPE=native` mode with declared host tool
dependencies: Rust 1.99.0, cargo-c 0.10.25 and the matching target std package.
The target ABI name remains `aarch64-unknown-netbsd`. Native build scripts and
procedural macros use the Mac compiler and archiver; target code uses the
accepted GCC16 wrappers, fork sysroot and runtime. No Rust, LLVM or GCC rebuild
is part of this consumer recipe. Rust source locations are remapped so panic
strings do not retain private build paths.

Meson's cross machine file selects the target ELF `nm` and `strip` tools.
The scanner canonicalizes include paths. A recipe-local compiler transform
maps the real sysroot prefix back into the declared buildlink tree, including
when the configured sysroot is a symlink. A negative control removes just
this transform and reproduces the missing Cairo header failure.

The explicit `emberbsd_gi_cross` path selects native scanner/compiler tools and
the shared [real target query launcher](introspection.md). Native builds keep
upstream behavior. A cross build without that explicit path still refuses
enabled introspection. No executable emulator or false `can_run_host_binaries`
answer is used.

The same explicit cross configuration supplies the SVG module installation
directory under the target prefix. This prevents pkg-config's sysroot-rebased
lookup path from appearing in the package; native directory selection is
unchanged. The regression executes both selections and checks the actual
module installation path in Meson's generated target metadata.

The inherited pkgsrc big-endian fixes were refreshed for matrixmultiply
0.3.11, memchr 2.8.3, wide 1.7.1 and zune-jpeg 0.5.15. New matching NEON branches
in wide use the same scalar fallback. These changes retain their pkgsrc
authorship and checksum records. This work validates little-endian AArch64;
it does not establish big-endian runtime support.

Upstream Meson and Cargo wrappers still use Python. These are existing build
dependencies, not new project-owned Python helpers. The optional `doc` option
remains off by default; upstream Vala bindings require an independently selected
native Vala provider. Neither is part of the default pkgsrc payload.

## Build and checks

Prepare the common graphics export, the shared native tool packages, the
accepted cross sysroot, and the GI query configuration described in the linked
instructions. Keep work, temporary files and packages on the selected build
volume. Use a bounded `MAKE_JOBS`, such as 2. Coordinate target access before
the build reaches GIR generation.

```sh
sh scripts/prepare-pkgsrc.sh /absolute/new-pkgsrc common-graphics
cd /absolute/new-pkgsrc/graphics/librsvg
env TMPDIR=/absolute/build-tmp MAKECONF=/absolute/cross.mk.conf bmake package
env TMPDIR=/absolute/build-tmp MAKECONF=/absolute/cross.mk.conf bmake install
```

`install` registers the package in the private cross sysroot. It does not
install base files or packages on the board. Keep sysroot source revisions,
artifact hashes and accepted provenance limitations with the build record.
The inherited NetBSD ABI names do not authorize an upstream base replacement.

Set the query configuration's `library_dirs` to the accepted target GCC16
runtime directory, as described for [GdkPixbuf](gdk-pixbuf.md). This selects one
runtime provider consistently across the executable and its dependencies.
The AVIF option also admits dav1d through librsvg's consumer buildlink because
the generated pkg-config metadata lists it in `Requires.private`.

The following regressions check the actual patched source and completed build:

```sh
ruby profiles/common-graphics/tests/librsvg-inputs.rb \
  /absolute/original-librsvg-source /absolute/built-librsvg-source \
  /absolute/distfiles
ruby profiles/common-graphics/tests/librsvg-cross.rb \
  /absolute/built-librsvg-source /absolute/native-prefix \
  /absolute/cross-tools/bin/aarch64--netbsd-gcc /absolute/new-selection-work
```

The first checks the unchanged upstream lock, every crate archive, all vendor
directories and patch checksums. The second checks that header transform and
executes the real Meson guard fragments for native, default cross and explicit
cross configurations, then checks native generator selection, the target
module installation path and actual full-build outputs.

## Packaged target consumer

[`prepare-librsvg-package.rb`](../tests/prepare-librsvg-package.rb) compares
every installed package file and symlink against the archive and cross-builds
[`librsvg-package.c`](../tests/librsvg-package.c). It embeds those exact files,
their required metadata, and two hash-pinned fixtures from the upstream source:
the Ahem font and `rectangle.avif`. The embedded font retains its public-domain
notice. Upstream font notes, authors and LGPL text accompany the fixtures.

```sh
ruby profiles/common-graphics/tests/prepare-librsvg-package.rb \
  /absolute/cross-tools /absolute/sysroot \
  /absolute/packages/librsvg-2.63.2.tgz /absolute/original-librsvg-source \
  /absolute/build-root/new-consumer
env EMBERBSD_GI_QUERY_CONFIG=/absolute/query.json ruby \
  profiles/common-graphics/recipes/devel/gobject-introspection/files/target-query.rb \
  /absolute/build-root/new-consumer/librsvg-package
```

The consumer belongs inside the configured query build root. It renders known
red, green and blue pixels through the C API, CLI PNG and dynamically queried
SVG loader. It also checks embedded AVIF pixels, text with the isolated Ahem
font, and a constructor invoked through the installed Rsvg typelib. Four
create/render/destroy cycles must pass; malformed SVG must fail in both C and
CLI paths. Loader or transport failures are failures, not passing negatives.

The launcher stages the recursive target ELF providers in a private temporary
directory, verifies hashes, enforces a timeout, records status and cleans up.
The consumer creates its own loader cache and font configuration there. No
board package registration, global loader cache or font cache is changed.

This is bounded CPU renderer acceptance. GPU rendering, a Wayland surface,
labwc integration, the complete upstream test suite and long-duration operation
require their own checks. Renderer warnings remain in the private build log.
