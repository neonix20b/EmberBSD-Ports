# Focused native prerequisite evidence

On 2026-10-07 the AArch64 NetBSD-derived recovery VM ran two bounded checks
from Ports `e2fc4d79d886b00667788a543ca41bde7abf5f5c`, using the already
installed GCC16.2 compiler and native `/usr/bin/make` (BSD make).

The source inputs were exact verified Python3.14.8 files plus the retained
pkgsrc pymacro patch. The proposed upstream array-derived faulthandler count
was compiled directly; the manual-count recipe patch was not used by this
fixture. Actual record/signal typedefs and handler arrays were extracted,
including both HAVE_SIGACTION branches and optional SIGBUS/SIGILL combinations.

- Eight initializer variants compiled and ran successfully with GNU11,
  `-Wall -Wextra -Werror`; intentionally omitted trailing fields are the
  sole named warning exclusion, matching production initialization.
- Pointer misuse failed compilation with the real macro's negative array
  bound. The contract required this rejection; it did not count it as an
  unexpected test failure or compare compiler-specific sentinel values.
- BSD make parsed the actual pkgsrc selection block. Default314 passed;
  old CLI313, unsupported314, incompatible314 and consumer exclusion all
  published the required failure reason, with no older fallback.
- The wrapper retained actual statuses and finished0. Run2 log SHA256:
  `5f234dea5b9ea252a439d54466b91b40010b3c925e6ecb564ad0fe838632a12c`.

Run1 stopped before manifest verification or compilation: a macOS provenance
extended attribute made NetBSD tar exit1. That setup failure remains recorded.
Run2 used the same verified sparse files repacked without xattrs/ACLs/flags
and checked the unchanged source SHA256SUMS. No failed tests were accepted.

This evidence permits removal of the redundant inherited faulthandler count
workaround from the common Python recipe, retaining upstream's array-derived
count and the NetBSD pymacro constant-expression assertion. It does not
prove full extension compilation, configured Python packages, LLVM23 compiler
acceptance, Meson-installed ELF behavior, Mesa26 or common-stack cutover.
No packages/defaults were changed or full GCC suite altered by these checks.

The removed workaround originated in pkgsrc `patch-Modules_faulthandler.c`,
RCS revision1.1, 2025-10-08 07:13:08, author `adam`, described as a GCC15
initializer workaround. Its original text and identifier remain in the pinned
pkgsrc source and preceding Ports commit; no authorship is reassigned.

## LLVM family selection and real GCC metadata

On 2026-10-07, a second bounded NetBSD/AArch64 check used frozen Ports
`cbf5c75c4a05f277a94d2b13a3dd9c8b432bafeb` and its exact recipe export.
Native BSD make passed four prepared-family paths and thirteen refused paths
using the production version selection block. Full package parsing remains pending.

The production native-gcc-config.sh generated a private native-triple config
from installed GCC16.2.0 and existing Clang21.1.8 metadata. It selected the
three actual GCC C++ include directories, exact private CRT directory, private
and runtime linker directories and runtime RPATH. The resulting config was
not installed or activated, and no LLVM23 driver or native link was exercised.

The wrapper returned 0. Log SHA256:
`2a0f3a4e5c4809e36b56fa10bfe2e103410a5c7bfebe8c4eb5cb269792d0ab2e`.
Receipt SHA256:
`6411e3e2ce7bad8cfb91c786659ffc2fa9bcc174d6c708d84a925c30af79cffb`.
The matching source archive SHA256 was
`8df5b0398b9ec6d8d6e495ce105fed84c7ba9185d3f79cf0b7b4163b3f84cceb`.
These checks do not accept the preceding incomplete generated-header PLIST,
LLVM23 packages/check-files, CMake exports, wheel payload, CRT/ELF runtime,
JIT, TinyGo or Mesa26. The source PLIST repair has its own causal regression.
