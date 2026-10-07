# GCC16 cross compiler for AArch64 EmberBSD

Cross-compilation is the preferred build path: build GCC 16.2.0 on the
development host and execute the resulting programs on EmberBSD. The tested
host is Apple Silicon macOS. There is no NetBSD-host
check in the compiler build or compile-only acceptance scripts. The separate
target runner requires AArch64 NetBSD because it executes target ELF files.

The compiler uses the same verified original GCC archive and frontend
portability patches as the Ports native package, including the nb1 C++
modules repair. This is a compiler build, not a cross-built pkgsrc package
or a complete distribution image. The target GCC16 runtime is taken from
an accepted sysroot; it is not rebuilt or installed by this recipe.

## Inputs

Prepare the development-toolchain or common-tools pkgsrc export using
[the parent profile](../README.md). Record the Ports commit and the sysroot's
source/package revisions and checksums. The archive URL and SHA256 are in
[the shared source manifest](../sources.tsv). Keep binary inputs outside Git.

Provide these absolute paths without whitespace:

1. The prepared pkgsrc tree containing `lang/gcc16` and the modules repair.
2. The original `gcc-16.2.0.tar.xz` archive.
3. An AArch64 EmberBSD sysroot with `/usr/include`, startup objects, libc,
   pthread and math libraries, loader, and the selected `/usr/pkg/gcc16`
   headers/runtime. Preserve relative symlinks. Resolve links escaping the
   sysroot when creating the snapshot; never resolve them against the host.
4. A host `TOOLDIR` produced by the fork's
   [cross-build path](https://github.com/apovalixin/EmberBSD/blob/main/ember/boot/cross-build.md).
   Its static GMP/MPFR/MPC and GNU make bootstrap the compiler, and its
   AArch64 binutils are copied into the compiler prefix. This is temporary
   bootstrap support, not a downgrade of target dependencies. The in-tree
   bootstrap currently contains older tools; qualifying current binutils
   and rebuilding this prerequisite closure remains separate work.
5. A new work directory with room for sources, objects and the compiler.

Use native compilation only for stages whose missing cross support is
identified explicitly; port those stages through Ports. The compiler and
linker must run on the build host. The sysroot libraries
and startup objects must belong to the target. Equal CPU architecture does
not make Darwin and NetBSD executables interchangeable.

```sh
CROSS_JOBS=6 HOST_CC=cc HOST_CXX=c++ \
    sh profiles/development-toolchain/cross/build.sh \
    /absolute/pkgsrc /absolute/gcc-16.2.0.tar.xz /absolute/sysroot \
    /absolute/os-build/tools /absolute/new-gcc-cross
```

The recipe verifies the GCC SHA256 and recorded RCS-filtered patch hashes
before extraction. It applies the source patches with zero fuzz. As in the
native common profile, Graphite/ISL is disabled. The source archive does not
contain ISL; its unused distinfo entry is excluded explicitly.

One additional cross-only difference is necessary: `patch-gcc_Makefile.in`
is verified but not applied. That native pkgsrc patch embeds the compiler's
installation prefix as target runtime search paths. On macOS that would
leak a Mac path into the ELF link or fail linking outright. The cross build
retains upstream's default driver search logic. The acceptance recipe
selects the target GCC16 startup objects, headers and runtime explicitly.
This does not remove the RPATH repair from native packages.

The recipe installs into `new-gcc-cross/toolchain` and records inputs and
build logs in the work directory. It never writes `/usr/bin`, `/usr/pkg`,
`/etc/mk.conf` or a board. Keep the work directory and sysroot at their
recorded paths. `HOST_CC`/`HOST_CXX` name the existing host compilers;
`CROSS_JOBS` controls concurrency. A failed stage returns nonzero.

## Compile here, execute on EmberBSD

```sh
sh profiles/development-toolchain/cross/compile-tests.sh \
    /absolute/new-gcc-cross/toolchain /absolute/sysroot /absolute/new-tests
```

This reuses the native C11 atomics/TLS and C++20 DSO test sources. It compiles
C with and without LTO, and C++ with threads, TLS, strings and exceptions
crossing a shared-library boundary. It checks dynamic dependencies for host
path leakage. Compilation alone is not runtime acceptance.

Copy the complete `new-tests` directory to a scratch directory on the target,
then run:

```sh
sh /absolute/target-tests/run-target.sh /absolute/target-tests
```

For archives made on macOS, use `COPYFILE_DISABLE=1 tar --no-xattrs --no-acls
--no-fflags ...` so NetBSD tar does not fail restoring Apple metadata.
The target runner checks actual loaded `libstdc++` and `libgcc_s` identities
against the already installed `/usr/pkg/gcc16` compiler. Loader overrides
are rejected. It does not install packages or change login defaults.

## Validation boundary

The host compiler build and cross C11/C++20 acceptance pass on Apple Silicon
macOS and physical Orange Pi Zero 3W (Allwinner A733), respectively. The target
runs the existing current EmberBSD kernel/libc and GCC16 nb1 runtime.
This covers the focused source scenarios, not the full upstream compiler
suite, arbitrary Ports packages, a full GCC16-built OS or GPU acceleration.

The common `mk.conf` still describes the **installed native compiler** policy.
Do not feed a target `/usr/pkg/gcc16/bin/gcc` to a Darwin build process.
General pkgsrc cross-package orchestration and Canadian-cross building of
an installable target GCC package require separate build/host/target handling.
The standalone cross compiler here is immediately usable for target source
compilation; its availability does not establish those package workflows.
