# DWARF format and expression acceptance

This suite exercises native GDB 18.1 on NetBSD 11/AArch64. Ports owns the
GDB adaptation and its debugger tests. The OS repository owns the separate
CTF converter; its single-primary-CU restriction is not a GDB restriction.
These fixtures and local patches are AI-assisted EmberBSD work.

## Build and run

Generate target executables with the accepted GCC 16.2 cross compiler and
complete sysroot. The GCC16 CRT directory is selected explicitly.

```sh
sh profiles/development-toolchain/gdb/dwarf-variants-build.sh \
    /absolute/current-gcc16/bin/aarch64--netbsd-gcc \
    /absolute/sysroot /absolute/new-fixtures
```

The builder records compiler and ELF-reader versions and debug metadata.
GCC's cross prefix can contain the older bootstrap readelf. The target
acceptance uses the selected Binutils 2.47 `greadelf`; use that version for
location-list interpretation. Base CRT objects can carry older DWARF CUs
alongside the fixture CU, so an executable's first CU is not necessarily
the tested source unit.

Transfer the complete fixture directory and the four target scripts to
the AArch64 VM. Prepare four indexed packages using the corrected LLVM
`llvm-dwp` 23.1.2 described below. Generate the two zstd inputs with LLVM
`llvm-objcopy` 23.1.2: the accepted Binutils 2.47 build lacks zstd compression.
A temporary packager and its libraries may be used privately; remove them
after packaging. Never pass its loader overrides to GDB acceptance.

```sh
OBJCOPY=/absolute/llvm-objcopy \
    sh dwarf-variants-package.sh /absolute/llvm-dwp /absolute/fixtures
sh dwarf-variants-target.sh /usr/pkg/bin/gdb /absolute/fixtures \
    /absolute/new-results
sh dwarf-variants-limits.sh /usr/pkg/bin/gdb /absolute/fixtures \
    /absolute/new-expression-results
sh dwarf-variants-ax.sh /usr/pkg/bin/gdb /absolute/fixtures \
    /absolute/new-agent-results
```

Packaging verifies that the DWP CU index contains both compilation units,
then removes only the generated standalone DWO inputs. The debugger runner
rejects a DWP case if any DWO remains in its directory. The original
cross-build path must not exist on the test target; do not mount it there.
Use a fresh build directory to regenerate inputs before repackaging.
On macOS, create transfer archives with `COPYFILE_DISABLE=1 tar --no-xattrs`
to avoid AppleDouble files being mistaken for standalone DWO inputs.

### DWARF64 packager correction

Unmodified LLVM 23.1.2 rejects the GCC DWARF64 inputs before GDB sees them.
DWARF4 reports `top level DIE is not a compile unit`; DWARF5 reports an
unknown abbreviation code. The header reader uses four-byte abbreviation
offsets and four-byte length fields even after detecting DWARF64. String
lookup and merging also assume four-byte string offsets.

`dwarf-variants-llvm-dwp.patch` corrects those widths for the fixture tool.
`dwarf-variants-dwp-build.sh` compiles its three translation units privately
against the selected LLVM 23.1.2 library and generated headers. It neither
edits nor installs the shared LLVM build. Use the same current GCC16 and
sysroot as the LLVM build; pass the LLVM project source root and its CMake
build directory:

```sh
sh profiles/development-toolchain/gdb/dwarf-variants-dwp-build.sh \
    /absolute/current-gcc16/bin/aarch64--netbsd-gcc /absolute/sysroot \
    /absolute/llvm-project-23.1.2.src /absolute/llvm-build \
    /absolute/new-private-dwp
```

If LLVM is not installed on the target, stage this tool, current
`llvm-objcopy`, and their existing `libLLVM.so.23.1` privately. Set
`LD_LIBRARY_PATH` only for the packaging command, then remove the temporary
tools and library. This pending upstream patch has been exercised on the
four two-CU C packages here. It is not a claim about every DWP producer,
mixed-width contribution, very large package, or type-unit package.

## Matrix

| Group | Cases | Required observation |
| --- | ---: | --- |
| C DWARF2/3/4/5, DWARF32/64, `-O0`/`-O2` | 16 | Two breakpoints, record members, scalar locals across a call, backtrace and normal exit |
| C++ DWARF4/5, DWARF32/64, type units | 4 | Signature-referenced template/inheritance types, optimized locals and normal exit |
| DWARF5 GNU and ELF zlib compression, DWARF32/64 | 4 | The same C debugging workflow using genuinely compressed sections |
| Separate `.gnu_debuglink`, DWARF32/64 | 2 | Stripped debug sections, external debug-file lookup and live values |
| DWARF4/5 indexed DWP, DWARF32/64 | 4 | Main-CU values and helper-CU argument at separate breakpoints, with no standalone DWO fallback |
| DWARF5 ELF zstd compression, DWARF32/64 | 2 | Compressed sections and the same live C workflow |

This is 32 compiler-produced debugging cases. Optimized cases verify actual
location lists and expressions, but do not enumerate every DWARF operation,
attribute, language or producer extension.

## Expression regression and local repair

`dwarf-variants-limits.S` supplies small, explicit DWARF5 units in both
DWARF32 and DWARF64. Every valid case must yield `variant_value == 42`.
The suite includes direct expressions, `DW_OP_call4`, same-CU and cross-CU
`DW_OP_call_ref`, constant `DW_OP_entry_value`, `DW_LLE_startx_length`,
`DW_LLE_startx_endx`, default locations and default/range precedence.
The cross-CU call enters a CU with the other offset width, performs a
CU-relative nested call and returns to another call in the original CU.
Malformed call operands and truncated default expressions must diagnose
truncation without crashing. There are 20 valid and four malformed cases.

The local `dwarf-variants-fixes.patch` adds `DW_OP_call_ref` to the expression
engine, symbol-requirement scanner and tracepoint expression compiler.
The called CU's context is restored after evaluation. It also adds
`DW_LLE_startx_endx` and default-location handling to the shared location
reader and location descriptions, with bounded expression lengths.
The lazy cross-CU lookup owns a symbol-expansion queue when invoked outside
symbol reading, processes it, and releases it before aging the CU cache.
Nested readers retain their caller's queue. The cross-CU fixture has no
address range in its second CU, so breakpoint lookup does not preload it.
The AX compiler independently bounds nested calls, frame-base expressions
and CFA expressions to 256 levels; tracepoint collection can bypass the
symbol-requirement scanner, so the scanner's guard is insufficient.
The patch has not been submitted or accepted upstream. Compilation alone
is not acceptance; compare the installed debugger before and after it.

`dwarf-variants-ax.sh` adds 14 agent-compiler checks: eight successful
direct/same-CU/cross-CU translations and six recursive `call2`/`call4`/
`call_ref` cases. A discarded register expression makes the requirement
scanner stop before the recursive call. The test accepts only the specific
AX recursion diagnostic, proving the AX compiler itself rejected the loop.
No running inferior or trace-capable remote target is needed. The six
recursive ELF fixtures are additional to the 24 runtime-expression inputs.

The fixture semantics follow [DWARF5 sections 2.5 and 2.6](https://dwarfstd.org/doc/DWARF5.pdf)
and the [standard's corrections](https://dwarfstd.org/errata-dwarf5.html).
In particular, `call_ref` is section-relative inside the current executable
or shared object; it is not an arbitrary reference into another module.

## Remaining limits

Upstream GDB 18.1's `gdb/dwarf2/expr.c` accepts `DW_OP_entry_value` only for
specific register or register-plus-dereference expressions. The valid
constant-expression case deliberately exposes that narrower evaluator;
fixing the three operations above does not remove it. General entry-time
memory/register reconstruction requires a separate design and tests.

The source also names narrower boundaries: skeletonless type units in DWP
without `.gdb_index`, `.debug_types` in an alternate/supplementary DWZ
object, and imported units within type units. Those source findings are
not executable coverage claims for this suite. Standalone supplementary
forms retain their separate acceptance in `test-target.sh`.

## Measured result

Native acceptance on NetBSD 11/AArch64 in UTM, 2026-10-08, used GCC 16.2.0
inputs and the installed `/usr/bin/gdb` wrapper for the GDB 18.1 package.
The installed ELF matched the rebuilt package and staged ELF:
`eb1c0bb10217764350b530fdf089b288f18a3ad913e0fa14da517645d9b55356`.
Package SHA256:
`a04fabdc497b7cc1f7a4c653d5834f545a47a36b92d17fede505fc9e8ef5419c`.

| Suite | Before the DWARF repair | Installed repair |
| --- | --- | --- |
| Compiler matrix | 30 PASS; both DWARF5 DWP cases fail | 32 PASS |
| Explicit expressions and malformed inputs | 6 PASS, 16 FAIL, 2 KNOWN_GAP | 22 PASS, 2 KNOWN_GAP |
| Agent-expression compiler | 4 PASS, 10 FAIL | 14 PASS |

Four additional DWP runs explicitly stopped in the helper CU and read
`*value == 41`, then continued to the main CU's second breakpoint and normal
exit. All four passed. The target runner includes this assertion for each
DWP case; the evidence preserves these later transcripts separately.

Both known gaps are the valid constant `DW_OP_entry_value` expression,
in DWARF32 and DWARF64. The exact diagnostic is:

```text
DWARF-2 expression error: DW_OP_entry_value is supported only for single DW_OP_reg* or for DW_OP_breg*(0)+DW_OP_deref*
```

The expression runner deliberately returns nonzero while these gaps remain.
The unpatched AX recursion controls ran with CPU/core bounds and exposed
call2/call4 stack exhaustion. The repaired cases emit the specific AX
recursion-limit diagnostic. The archived evidence includes each transcript,
input index and hash. Archive SHA256:
`237d39d1d9365cd3bff91a468c51000069ed02164203261e31039059a7400381`.

No result here establishes universal DWARF conformance, physical-board
ptrace behavior, kernel core dumps or the complete upstream GDB testsuite.
