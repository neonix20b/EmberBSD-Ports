# Reconstructing DWARF entry values

GDB 18.1nb1 evaluates scalar `DW_OP_entry_value` and `DW_OP_GNU_entry_value`
operands with a separate, initially empty stack. This allows constants,
arithmetic, branches, nested entry expressions and DWARF procedure calls.
The operand must return exactly one value. A register location description
is the compact alternative allowed by
[DWARF5 section 2.5.1.7](https://dwarfstd.org/doc/DWARF5.pdf).

The owning Ports patch is [dwarf-variants-fixes.patch](dwarf-variants-fixes.patch).
It builds on the upstream GDB 18.1 evaluator and call-site reconstruction;
FSF copyright and GPLv3 notices remain in the source. The adaptation and
regressions are AI-assisted EmberBSD work, not submitted or accepted upstream.

## Entry state and current state

At a function's first instruction in the innermost frame, current values
are entry values. After execution advances, register reads use the caller's
`DW_TAG_call_site_parameter` and `DW_AT_call_value`. Nested call-value
expressions use the caller's context, including unwound saved registers.
`breg`, `bregx` and typed register operations can combine reconstructed values.
Typed results preserve raw register bits, including floating-point values and
128-bit SIMD registers; they do not numerically cast floating-point bits.
If metadata supplies fewer bits than the requested register value, the value
is unavailable. Unknown high bits are not invented.

The existing `breg(0); deref`/`deref_size` form still uses
`DW_AT_call_data_value`. General historical memory reads have no snapshot:
they return unavailable instead of reading current memory. Historical
frame-base/CFA, TLS and variable-value expressions likewise need reconstruction
that this patch does not supply. Missing call-site metadata returns unavailable.
GDB usually displays these `NO_ENTRY_VALUE_ERROR` results as optimized out.
These are missing historical inputs, distinct from rejecting constant or
reconstructible register arithmetic merely because of the operand's syntax.

Nested evaluators retain the recursion budget and CU context. Returning from
one restores the enclosing stack and its evaluation mode. Fixed operands,
block lengths and branch destinations are checked before access;
`DW_OP_push_object_address` is rejected inside an entry operand as required by
the standard. This is bounded expression support, not a claim that every
DWARF operation or source-language debugger workflow has been validated.

## Reproduce

Build the two AArch64 executables on the development host:

```sh
sh profiles/development-toolchain/gdb/dwarf-entry-value-build.sh \
    /absolute/current-gcc16/bin/aarch64--netbsd-gcc \
    /absolute/sysroot /absolute/new-entry-fixtures
```

Transfer the complete fixture directory and the target runner to NetBSD
11/AArch64, then test the selected debugger without loader overrides:

```sh
sh dwarf-entry-value-target.sh /absolute/gdb /absolute/entry-fixtures \
    /absolute/new-results
```

The assembly fixture supplies explicit DWARF32 and DWARF64 units. The caller
passes 40 and 2 in registers and 42 through memory. The callee changes them to
100, 9 and 99 before the main breakpoint. It also changes the saved-register
source of the caller's call-value expression and the typed float/SIMD registers.
Every test verifies those actual stopped values before evaluating the variable.
Controls stop at the first instruction and verify the original values.

The 72 checks cover constants, GNU spelling, arithmetic, a taken branch,
nested expressions, stack isolation, register arithmetic, call-value context,
typed float32 and 128-bit SIMD values, data-value recovery and unavailable
history. They also reject empty/multiple/pieced results, stack underflow,
truncated or overflowing block lengths, truncated LEB/fixed/typed operands,
out-of-range branches, forbidden object addresses and recursive entry calls.
The runner requires normal inferior exit and rejects debugger crashes.

## Verification

On 2026-10-08 the macOS/GCC 16.2 cross build passed all 72 checks first with the candidate and then with the installed
GDB 18.1nb1 package in NetBSD 11/AArch64 UTM. Their identical ELF SHA256 was
`f70bf959a177e413d511c02808bfd5485765e2e37800fe8ab33ca8341f4f0b42`.
The same suite against the original installed GDB 18.1 yielded 8 PASS and
64 FAIL; its RED transcript is retained separately. The corrected debugger
also passed the existing 24 expression/location and 14 agent-compiler checks.
A first implementation additionally failed the typed float and SIMD cases;
raw-bit preservation and full reconstructed widths fixed both regressions.

This result does not establish physical-board debugging, execution-history
recording or the complete upstream GDB testsuite. Package installation and
image acceptance are recorded separately in [package.md](package.md).
