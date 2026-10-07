# Native compiler selection

This opt-in check packages a small C/C++20 consumer through actual pkgsrc
wrappers and the common-tools MAKECONF. It verifies the full GCC16 dependency,
installed execution, exceptions, and loaded GCC16 C++/unwind libraries.
It uses normal package and file checks, then removes only its test package.
The fixture itself does not select system defaults or rebuild GCC prerequisites.

Run as root on native NetBSD 11/AArch64 after installing repaired GCC 16.2.0nb1 or newer,
cwrappers, mktools and checkperms. Use a prepared common-tools pkgsrc export
and either the [durable default](../../development-defaults.md) `/etc/mk.conf`
or a private MAKECONF that includes `EMBERBSD-COMMON-TOOLS-MK.CONF`.
The configuration must define `PREFIX=LOCALBASE=/usr/pkg` before the include;
the runner supplies no prefix override.
Use a new absolute work directory; paths must not contain whitespace.

```sh
sh run.sh EXPORTED_PKGSRC MAKECONF NEW_WORK
```

Run under the device's normal bounded build/resource supervisor with one
compiler worker. Outputs, statuses, source bytes, package hash, link/runtime
receipts and removal log remain in NEW_WORK. A temporary private category
is removed from the export. No loader overrides are allowed.

The original recipe and unchanged C/C++ source bytes passed native
compile/link/package/install/runtime checks on Orange Pi Zero 3W A733.
The original runner passed the same native gate with GCC 16.2.0, including a
GDB stop at the
exported `__cxa_throw` symbol in the stripped installed executable. The updated
runner passes with installed `gcc16-16.2.0nb1` through actual
`/etc/mk.conf`, including the repaired minimum, full/no-libs policy, normal
check-files, installed execution, GDB runtime inspection and package removal.
This focused
contract does not establish GCC self-hosting, complete upstream-suite success,
C++ modules support, or migration of optional GMP C++ consumers.
Reuse [the development runtime check](../../../development-toolchain/tests/run.sh)
for the broader atomics/TLS/thread/shared-library contract.

These are original AI-assisted EmberBSD test fixtures under BSD-2-Clause,
not upstream GCC tests or an installable product package. pkgsrc framework
files retain their upstream licenses and identifiers.
