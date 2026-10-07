# GCC 16.2 native validation

The ready `gcc16-16.2.0` package runs on the physical Orange Pi Zero 3W
(Allwinner A733, NetBSD 11/AArch64). It was built once in the AArch64 UTM
environment and reused unchanged. Its SHA256 is
`ac0dae96d79c0568ce1aa9d8d1c861dfda3d1defa9a59bfb6a6ff72adad06559`.
These results describe the installed compiler and named consumers. They do
not accept the complete upstream suite, a self-hosted build or a release image.

## Current prerequisite packages

The board uses the current EmberBSD kernel and complete corrected shared and
static libc. The compiler dependency set is GMP 6.3.0, MPFR 4.2.2, MPC 1.4.1
and libxml2 2.15.4. Base GCC 12.5 supplied the bootstrap compiler.

MPFR and libxml2 passed ordinary native pkgsrc build, test, DESTDIR staging,
check-files and package creation. MPFR reports 195 passes and three skips
out of 198 tests, with no failures or errors. Decimal64, decimal128 and
`_Float128` tests skip under the inherited NetBSD configuration; they are
not counted as passes. The installed MPFR DSO uses the selected GMP C DSO.

The unchanged MPC package passes all 75 upstream tests against MPFR 4.2.2.
The tests-only build uses normal pkgsrc wrappers and upstream test sources.
Private build-tree symlinks resolve to the installed MPC files; the loaded
DSO identities and hashes were recorded. Earlier wrapper/search-path setup
failures happened before arithmetic tests and remain in the evidence.

| Native package | SHA256 |
| --- | --- |
| MPFR 4.2.2 | `48da921046b8f9b9bdf1a088e54b5e763bfc833cc11ef44be5801a558934d1c0` |
| libxml2 2.15.4 | `8e1f9b4987c0f9383f5f295c58dad227e98983d1553e1bfe4cb3da7badeb7bca` |

Temporary old Libtool/pkgconf bootstrap tools were removed with pkg_delete
after confirming no full reverse dependencies. The GMP snapshot contains an
optional old-runtime C++ library; only its C DSO is accepted in this compiler
closure. New GCC16 C++ consumers must not use that old libgmpxx.

## Compiler and generated programs

The existing [native compiler checks](tests/run.sh) pass C11 atomics, pthreads,
C/C++ TLS, C++20, cross-DSO string exchange and exception cleanup. The actual
consumer process loads one libstdc++.so.7 and one libgcc_s.so.1 from the selected
GCC16 prefix. No loader override or SONAME alias conceals old dependencies.
The compiler driver and cc1/cc1plus/lto1 have their own recorded bootstrap
runtime dependencies; none loads libgmpxx or the old libstdc++.so.9.

The original atomic and binary128 LTO regression sources pass with and without
the linker plugin against the installed corrected system libc. These four
checks no longer link replacement libc objects explicitly.

The [native pkgsrc fixture](../common-build-tools/tests/native-compiler-selection/README.md)
also passes actual wrappers, normal staging/check-files, package installation,
C/C++20 execution and loaded-runtime checks. Its generated full dependency
retains gcc16, without gcc16-libs. GDB stops at the exported exception symbol
in the stripped consumer and records the loaded libraries before normal exit.
The temporary consumer package is removed after the check. The fixture is
versioned in Ports commit `cf99d8b34ef496bf69d8053aa745bda187560242`.

Native logs retain upstream test diagnostics, libtool staging warnings and a
GDB missing-source warning. They do not alter the successful checks above.
No vulnerability-database check is claimed; the test host lacked that database.

## Boundaries

The completed original VM upstream suite returned status 1 on its earlier
kernel/libc. Its logs remain unchanged; the board subset does not turn that
baseline into a successful full suite. A module exporter still reproduces an
ICE because NetBSD returns EOPNOTSUPP from posix_fallocate; the
[source repair](modules-portability.md) and its native/package acceptance are
tracked separately. No complete C++20 modules support is claimed here.

The VM's old Qt/ICU/LLVM closure still requires coordinated rebuilding.
Current binutils, self-hosting and complete base/image integration are separate
gates. Installing the package does not replace /usr/bin/cc or all system C++
libraries. Follow the [common profile](../common-build-tools/README.md) for
new pkgsrc consumers and retain the documented bootstrap boundary.
