# Current common build tools

This profile prepares one common Python 3.14.8 and Meson 1.12.1 for the
GCC 16 / LLVM 23 / Mesa 26 dependency closure. Source preparation and host
contracts are available. Native packages, package-file checks, installed
extensions and consumers remain pending. This is not an installed Mesa stack.

The profile owns the full `lang/python314` and `devel/meson` recipes, based on
pkgsrc `fff4deb639a1a640476203c80f752fb77b6cb14b`. It composes the established
[development toolchain](../development-toolchain/README.md) export without
changing GCC recipes, compiler selection or bootstrap options. The default
export and `development-toolchain` mode retain their previous behavior.

## Prepare and select

```sh
git submodule update --init --depth 1 upstream/pkgsrc
sh scripts/prepare-pkgsrc.sh /absolute/new-pkgsrc common-build-tools
```

The destination must be new. The exporter rejects missing required patches
before creating it. Original archive URLs and SHA256 are in
[sources.tsv](sources.tsv); recipes record BLAKE2s, SHA512, size and pkgsrc's
RCS-filtered patch SHA1. Meson uses its release asset, not GitHub's generated
source tarball. No archives, build outputs or local machine settings belong
in Git.

A later native build's private MAKECONF includes the exported
`EMBERBSD-COMMON-TOOLS-MK.CONF`. Include `EMBERBSD-DEVELOPMENT-MK.CONF` only
when its documented C/C++ options are also intended. The common-tools file
requires Python 314 and Meson >=1.12.1, uses one worker and rejects cross
package builds. It does not set `GCC_REQD` or activate a compiler by default.
Parent native work selects the already built current compiler explicitly.

The opt-in `lang/python/pyversion.mk` guard rejects unsupported consumers
and older command-line interpreter overrides. Repair those consumers through
Ports; do not select an old interpreter or install another one beside this
stack. This source stage does not uninstall existing packages or change
system defaults. Later package migration must check their reverse dependencies.

## Patch decisions

Original pkgsrc identifiers, ownership and upstream licenses are preserved.
Local adaptations and shell/C contracts are AI-assisted EmberBSD work;
these adaptations have not been submitted or accepted upstream.

| Python patch | Decision and reason |
| --- | --- |
| `Include_pymacro.h` | Retain NetBSD/SunOS constant-expression assertion. |
| `Lib___pyrepl_terminfo.py` | Retain NetBSD terminfo.cdb via ctypes and tmux alias. |
| `Lib_ctypes_util.py` | Retain PREFIX/X11 clang search and conditional SunOS lookup. |
| `Lib_sysconfig_____init____.py` | Retain coupled platform-only sysconfig and config-directory naming. |
| `Makefile.pre.in` | Retain install ordering, optimization levels 0/1, naming and suppression of generic libpython3.so; correct the policy description. |
| `Modules_faulthandler.c` | Retain manual count until the actual macro/initializer contract passes native GCC16; host success is insufficient. |
| `Modules_readline.c` | Retain selected readline portability; editline is not accepted here. |
| `Modules_socketmodule.c` | Retain conditional SunOS declaration. |
| `configure` | Retain packaging/UUID hunks; remove blanket cross-validation bypass. |

The Python PLIST adds the two upstream test modules `test_capi/test_slice`
and `test_free_threading/test_context`, each with source and optimization
levels 0/1. Buildlink's config directory matches the installed
`config-3.14` directory. No generic libpython SONAME alias is created.
The recipe uses upstream's shipped `configure`, without autoreconf;
`configure.ac` is unchanged. Regeneration needs a separate synchronized
source/generated patch review. NetBSD still selects pkgsrc libuuid instead
of its system's UUIDv4-only interface.

| Meson patch | Decision and reason |
| --- | --- |
| `compilers_detect.py` | Retain only `cython-3.14`; upstream already supplies stdin language, so drop the suffix heuristics. |
| `compilers_mixins_gnu.py` | Retain conditional SunOS as-needed handling. |
| `dependencies_dev.py` | Explicit LLVM config-tool selection fails closed and cannot fall back through CMake. |
| `linkers_linkers.py` | Retain SunOS thin-archive restriction; drop unconditional rpath-link override. |
| `modules_pkgconfig.py` | Retain foreign pkg-config directory placement. |
| `scripts_depfixer.py` | Drop NetBSD ELF-fixup bypass; retain upstream install RPATH processing. |

Machine-file `llvm-config` entries retain upstream precedence over the
`LLVM_CONFIG_PATH` environment variable, including failure. Without a
machine entry, an explicit environment path must be absolute and must meet
the requested version. Missing, invalid or wrong-version tools cannot fall
back to suffixed/default tools or CMake. Native/build-machine selection may
use that environment path; a cross target uses its own machine file and
never imports the native environment selection. With no explicit selection,
upstream automatic dependency discovery remains available.

## Reproducible source checks

Save original archives in a private directory, using the URLs in sources.tsv.
The source check requires a C/C++ compiler, Python >=3.10 to run upstream
Meson, and an OpenSSL implementation with BLAKE2s support. Set `PYTHON`,
`CC`, `CXX`, `OPENSSL` or `BMAKE` explicitly when necessary.

```sh
sh profiles/common-build-tools/tests/source-profile.sh \
    /absolute/verified-distfiles /absolute/new-source-check
```

The test verifies archives and all 14 patches through actual pkgsrc
`checksum.awk`, rejects corrupted archives, unfiltered patch hashes,
missing patches and repeated application, and applies the full series
forward with zero fuzz. It checks PLIST additions and restored upstream
ELF fixup, exports exact recipes, compares unchanged GCC recipe composition,
and rejects existing destinations and unknown profiles. Logs and extracted
sources remain in the private output directory.

Actual Meson CLI fixtures exercise C++20 through a compiler proxy and ten
LLVM selection cases. Fake LLVM metadata proves tool choice/error handling;
it does not prove LLVM headers, libraries, ELF linkage or execution.
`MESON_SELECTION_CASE=missing` isolates the causal baseline: the original
pkgsrc patch accepts a missing path using `llvm-config-64`; the new patch
refuses it. The fixture preserves the actual configure statuses.

`tests/python-selection.sh EXPORTED_PKGSRC NEW_WORK` parses the actual
pkgsrc selection block with BSD make. It checks default 314, rejected old
CLI selection and unsupported/incompatible consumers. If BSD make is absent,
the source check prints an explicit SKIP; native parsing remains required.

The faulthandler compile gate is independently usable by a native parent:

```sh
CC=/absolute/current-cc sh profiles/common-build-tools/tests/faulthandler-macro.sh \
    /absolute/fully-patched-python /absolute/pristine-python /absolute/new-macro-check
```

It extracts the actual record/handler array and upstream count initializer,
includes the patched production pymacro header, covers optional SIGBUS/SIGILL
combinations with both actual HAVE_SIGACTION layouts, and requires pointer
misuse to fail compilation. The signal typedefs are extracted from upstream;
only the declaration-only visibility macro for unrelated prototypes is supplied.
Host builds select the NetBSD
macro branch after their system headers; they are not NetBSD execution proof.
The sole suppressed warning covers intentionally omitted trailing record
fields, as in the production initializer. Native GCC16 evidence is required
before dropping the count workaround; LLVM23 should check the same contract.

## Native acceptance still required

Use staged packages and normal pkgsrc checks; do not bypass missing files,
WRKREF, RPATH, checksum, dependency or upstream test failures.

- Python: package/check-files, sysconfig/config script/pkg-config agreement,
  installed `_ctypes`/libffi, OpenSSL, libuuid, readline and PyREPL/terminfo.cdb;
  extension compile/import and embedded interpreter with the selected runtime.
- Meson: installed CLI/upstream tests, explicit native/cross LLVM selection,
  real installed shared-library fixture with transitive PREFIX dependencies,
  build-path/X-padding removal, intended install_rpath and clean execution.
- Common consumers: current setuptools/wheel/Cython dependencies, LLVM23
  generators, Mesa26 configuration/build/tests and their ELF/runtime closure.

Native libpython and all C++ consumers must use the selected common runtimes.
Source/host checks do not establish those package, ELF or Mesa gates.
