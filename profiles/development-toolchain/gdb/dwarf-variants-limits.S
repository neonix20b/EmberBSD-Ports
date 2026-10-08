/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted), minimal standard DWARF5 limitations. */
/* KIND: 0 direct, 1 call4, 2 call_ref, 3 entry_value constant,
 * 4 default_location, 5 startx_endx, 6 startx_length, 7 cross-CU call_ref,
 * 8 default before matching range, 9 default after nonmatching range,
 * 10 truncated call_ref, 11 truncated default expression,
 * 12/13/14 recursive call2/call4/call_ref for the agent compiler. */
#ifndef KIND
#define KIND 0
#endif
#define LOC_KIND ((KIND >= 4 && KIND <= 6) || KIND == 8 || KIND == 9 || KIND == 11)
#ifdef DW64
#define OFFSET .quad
#else
#define OFFSET .long
#endif
	.text
	.globl main
	.type main,%function
main:
	mov w0,0
	ret
.Lmain_end:
	.size main,.-main
	.section .debug_abbrev,"",%progbits
.Labbrev:
	.uleb128 1
	.uleb128 0x11 /* compile_unit */
	.byte 1
	.uleb128 0x03; .uleb128 0x08 /* name, string */
	.uleb128 0x13; .uleb128 0x05 /* language, data2 */
	.uleb128 0x11; .uleb128 0x01 /* low_pc, addr */
	.uleb128 0x12; .uleb128 0x06 /* high_pc, data4 */
	.uleb128 0x73; .uleb128 0x17 /* addr_base, sec_offset */
	.byte 0,0
	.uleb128 2
	.uleb128 0x24 /* base_type */
	.byte 0
	.uleb128 0x03; .uleb128 0x08
	.uleb128 0x0b; .uleb128 0x0b /* byte_size, data1 */
	.uleb128 0x3e; .uleb128 0x0b /* encoding, data1 */
	.byte 0,0
	.uleb128 3
	.uleb128 0x34 /* variable */
	.byte 0
	.uleb128 0x03; .uleb128 0x08
	.uleb128 0x49; .uleb128 0x13 /* type, ref4 */
	.uleb128 0x3f; .uleb128 0x19 /* external, flag_present */
	.uleb128 0x02 /* location */
#if LOC_KIND
	.uleb128 0x17 /* sec_offset */
#else
	.uleb128 0x18 /* exprloc */
#endif
	.byte 0,0
	.uleb128 4
	.uleb128 0x36 /* dwarf_procedure */
	.byte 0
	.uleb128 0x02; .uleb128 0x18
	.byte 0,0
	.uleb128 5
	.uleb128 0x2e /* subprogram */
	.byte 1
	.uleb128 0x03; .uleb128 0x08
	.uleb128 0x11; .uleb128 0x01
	.uleb128 0x12; .uleb128 0x06
	.uleb128 0x49; .uleb128 0x13
	.byte 0,0
	.uleb128 6
	.uleb128 0x11 /* a second compile_unit, with no address range */
	.byte 1
	.uleb128 0x03; .uleb128 0x08
	.uleb128 0x13; .uleb128 0x05
	.byte 0,0
	.byte 0
	.section .debug_info,"",%progbits
.Lcu:
#ifdef DW64
	.long 0xffffffff
	.quad .Lcu_end-.Lcu_header
#else
	.long .Lcu_end-.Lcu_header
#endif
.Lcu_header:
	.short 5
	.byte 1,8
	OFFSET .Labbrev
	.uleb128 1
	.asciz "dwarf-variants-limits.S"
	.short 0x000c /* C99 */
	.quad main
	.long .Lmain_end-main
	OFFSET .Laddr_entries
.Lbase:
	.uleb128 2
	.asciz "int"
	.byte 4,5
	.uleb128 5
	.asciz "main"
	.quad main
	.long .Lmain_end-main
	.long .Lbase-.Lcu
	.uleb128 3
	.asciz "variant_value"
	.long .Lbase-.Lcu
#if LOC_KIND
	OFFSET .Llist
#else
	.uleb128 .Lexpr_end-.Lexpr
.Lexpr:
#if KIND == 0
	.byte 0x10; .uleb128 42 /* constu */
#elif KIND == 1
	.byte 0x99; .long .Lprocedure-.Lcu /* call4 */
#elif KIND == 2
	.byte 0x9a; OFFSET .Lprocedure /* call_ref, section-relative */
#elif KIND == 3
	.byte 0xa3; .uleb128 2 /* entry_value */
	.byte 0x10; .uleb128 42 /* constant expression at entry */
#elif KIND == 7
	.byte 0x9a; OFFSET .Lforeign_procedure
	/* This CU-relative call also proves restoration of the caller CU. */
	.byte 0x99; .long .Lprocedure-.Lcu
	.byte 0x22 /* plus: foreign 41 + local 1 */
#elif KIND == 10
	.byte 0x9a,0 /* deliberately too short */
#elif KIND >= 12 && KIND <= 14
	/* Make the symbol-requirement scanner stop at a frame dependency.
	 * The AX compiler still must inspect the recursive procedure below. */
	.byte 0x70,0,0x13 /* breg0(0), drop */
#if KIND == 12
	.byte 0x98; .short .Lprocedure-.Lcu
#elif KIND == 13
	.byte 0x99; .long .Lprocedure-.Lcu
#else
	.byte 0x9a; OFFSET .Lprocedure
#endif
#endif
	.byte 0x9f /* stack_value */
.Lexpr_end:
#endif
	.byte 0 /* end subprogram children */
.Lprocedure:
	.uleb128 4
#if KIND == 12
	.uleb128 3
	.byte 0x98; .short .Lprocedure-.Lcu
#elif KIND == 13
	.uleb128 5
	.byte 0x99; .long .Lprocedure-.Lcu
#elif KIND == 14
#ifdef DW64
	.uleb128 9
#else
	.uleb128 5
#endif
	.byte 0x9a; OFFSET .Lprocedure
#else
	.uleb128 2
#if KIND == 7
	.byte 0x10; .uleb128 1
#else
	.byte 0x10; .uleb128 42
#endif
#endif
	.byte 0
.Lcu_end:
#if KIND == 7
.Lforeign_cu:
/* Use the other DWARF offset width to check context-sensitive decoding. */
#ifdef DW64
	.long .Lforeign_end-.Lforeign_header
#else
	.long 0xffffffff
	.quad .Lforeign_end-.Lforeign_header
#endif
.Lforeign_header:
	.short 5
	.byte 1,8
#ifdef DW64
	.long .Labbrev
#else
	.quad .Labbrev
#endif
	.uleb128 6
	.asciz "foreign-procedure"
	.short 0x000c
.Lforeign_procedure:
	.uleb128 4
	.uleb128 5
	.byte 0x99; .long .Lforeign_leaf-.Lforeign_cu
.Lforeign_leaf:
	.uleb128 4
	.uleb128 2
	.byte 0x10; .uleb128 41
	.byte 0
.Lforeign_end:
#endif
	.section .debug_addr,"",%progbits
#ifdef DW64
	.long 0xffffffff
	.quad .Laddr_end-.Laddr_header
#else
	.long .Laddr_end-.Laddr_header
#endif
.Laddr_header:
	.short 5
	.byte 8,0
.Laddr_entries:
	.quad main,.Lmain_end
.Laddr_end:
	.section .debug_loclists,"",%progbits
#ifdef DW64
	.long 0xffffffff
	.quad .Lloc_end-.Lloc_header
#else
	.long .Lloc_end-.Lloc_header
#endif
.Lloc_header:
	.short 5
	.byte 8,0
	.long 0
.Llist:
#if KIND == 8
	.byte 0x05 /* default 99 must not hide the matching entry below */
	.uleb128 3
	.byte 0x10; .uleb128 99; .byte 0x9f
#endif
#if KIND == 9
	.byte 0x02; .uleb128 1; .uleb128 1 /* empty, nonmatching range */
	.uleb128 3
	.byte 0x10; .uleb128 99; .byte 0x9f
#endif
#if KIND == 4 || KIND == 9 || KIND == 11
	.byte 0x05 /* default_location */
#elif KIND == 5 || KIND == 8
	.byte 0x02; .uleb128 0; .uleb128 1 /* startx_endx */
#else
	.byte 0x03; .uleb128 0; .uleb128 .Lmain_end-main /* startx_length */
#endif
#if KIND == 11
	.uleb128 127 /* deliberately longer than the containing section */
#else
	.uleb128 3
#endif
	.byte 0x10; .uleb128 42; .byte 0x9f
	.byte 0
.Lloc_end:
	.section .note.GNU-stack,"",%progbits
