# Cross-build the graphics payload

The common tools and language packages own the compiler, sysroot and build
tools. This graphics-specific step consumes them without rebuilding LLVM,
Python or Meson. It builds the complete core-only libdrm 2.4.134nb1 payload
selected by the [canonical recipe](../recipes/x11/libdrm/Makefile).
Package creation/registration and the common Mesa/consumer transition remain
separate acceptance steps.

Use the [GCC16 cross compiler](../../development-toolchain/cross/README.md),
an AArch64 NetBSD 11 sysroot with its GCC16 CRT and base libpci, host Python
3.14.8 and the fully prepared common Meson 1.12.1 source. The sysroot must
contain real target libraries, headers and preserved SONAME links. Do not
substitute host libraries. The original libdrm URL and SHA256 are recorded
in [sources.tsv](../sources.tsv).

```sh
PYTHON=/absolute/python3.14 JOBS=4 sh build-libdrm.sh \
    /absolute/libdrm-2.4.134.tar.xz /absolute/cross-prefix \
    /absolute/target-sysroot /absolute/prepared-meson /absolute/new-work
```

The helper verifies the original archive and every recipe patch, applies
the full series with zero fuzz, selects native NetBSD atomics and retains
the recipe's core-only options, upstream tests and warning policy. Cross
compiler/linker inputs name only the target sysroot. The disabled pkg-config
lookup cannot import host optional libraries: this profile uses compiler
atomics and has no required external pkg-config dependency. A future module
requiring one needs a real target metadata path and a reviewed profile change.

`stage/usr/pkg` is compared with the complete canonical PLIST, including
symlinks. ELF metadata must not contain host work/compiler/sysroot paths.
`tests` contains the cross-built upstream hash, skip-list and device probes,
the upstream symbol checker and the same staged libdrm. Logs remain in the
work directory. Neither the helper nor the target test runner installs a
package, changes a desktop or restarts a VM.

Transfer `tests` into a new private directory on the target, preserving its
symlink. On macOS use `COPYFILE_DISABLE=1 tar --no-xattrs` to avoid carrying
Apple extended attributes into NetBSD. Verify SHA256 after transfer, then:

```sh
PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/pkg/bin \
    PYTHON=/path/to/existing/python sh run-libdrm-tests.sh
```

The runner checks the resolved libdrm path for all three ELF programs before
executing any of them. Missing, ambiguous or foreign loader resolutions fail;
the SONAME symlink must resolve to the staged DSO. Loader closures are retained.
`sh test-runner.sh` checks these refusals with mocked loader output; it does not
replace the actual target run.
The Python executable only runs upstream's symbol inspection; Python is not
a libdrm runtime dependency. A device-test status of 77 is reported as SKIP,
never rendering success. Host `meson test` skips target executables without
an execution wrapper; its symbol checker also assumes the running OS's
object format. Use the target checker until that upstream cross-test boundary
is adapted. A zero host test failure count is insufficient acceptance.

## Verified boundary

On 2026-10-07, Apple Silicon macOS/GCC16.2 cross-built the selected shared
library and all enabled test programs with normal `-Werror` and only the
existing unsupported-bus `-Wno-error=cpp` exception. All 26 staged files and
links matched PLIST. The target DSO needs only NetBSD libpci.so.2 and libc.so.12;
its SONAME is libdrm.so.2. No build-host path appears in its dynamic metadata.

In the AArch64 NetBSD 11 UTM guest, hash, drmsl and the actual exported-symbol
check passed. Device enumeration returned 77 with no attached DRM device on
the ordinary EMBER64 kernel. That check used the existing Python 3.13.14 only
for upstream's inspection script; it did not install or select an older
interpreter for the common stack. Package registration, a booted matched
EMBERGPU kernel, DRM identity/permissions, Mesa26/LLVM23 and an accelerated
Wayland session are not established by this result.
