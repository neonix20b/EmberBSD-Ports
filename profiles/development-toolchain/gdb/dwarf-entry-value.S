/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted), entry state differs from stopped state. */
#ifdef DW64
#define OFFSET .quad
#else
#define OFFSET .long
#endif
	.data
	.globl entry_cell
entry_cell: .word 42
	.balign 16
.Lwide_data: .quad 7,42
.Lfloat_data: .word 0x422a0000 /* 42.5f */
	.text
	.globl main
	.type main,%function
main:
	.cfi_startproc
	stp x29,x30,[sp,-32]!
	.cfi_def_cfa_offset 32
	.cfi_offset 29,-32
	.cfi_offset 30,-24
	mov x29,sp
	str x19,[sp,16]
	.cfi_offset 19,-16
	mov x19,39
	mov x0,40
	mov x1,2
	adrp x2,entry_cell
	add x2,x2,:lo12:entry_cell
	mov x3,43
	ldr q0,.Lwide_data
	ldr w4,.Lfloat_data
	bl entry_probe
.Lreturn:
	ldr x19,[sp,16]
	ldp x29,x30,[sp],32
	.cfi_def_cfa_offset 0
	mov w0,0
	ret
	.cfi_endproc
.Lmain_end:
	.size main,.-main
	.globl entry_probe
	.type entry_probe,%function
entry_probe:
	.cfi_startproc
	stp x29,x30,[sp,-32]!
	.cfi_def_cfa_offset 32
	.cfi_offset 29,-32
	.cfi_offset 30,-24
	mov x29,sp
	str x19,[sp,16]
	.cfi_offset 19,-16
	mov x19,77
	mov x0,100
	mov x1,9
	mov x3,99
	mov w4,99
	str w4,[x2]
	movi v0.16b,0
	.globl entry_stop
entry_stop:
	nop
	ldr x19,[sp,16]
	ldp x29,x30,[sp],32
	.cfi_def_cfa_offset 0
	ret
	.cfi_endproc
.Lprobe_end:
	.size entry_probe,.-entry_probe
	.section .debug_abbrev,"",%progbits
.Labbrev:
	.uleb128 1; .uleb128 0x11; .byte 1
	.uleb128 3; .uleb128 8
	.uleb128 0x13; .uleb128 5
	.uleb128 0x11; .uleb128 1
	.uleb128 0x12; .uleb128 6
	.byte 0,0
	.uleb128 2; .uleb128 0x24; .byte 0
	.uleb128 3; .uleb128 8
	.uleb128 0xb; .uleb128 0xb
	.uleb128 0x3e; .uleb128 0xb
	.byte 0,0
	.uleb128 3; .uleb128 0x2e; .byte 1
	.uleb128 3; .uleb128 8
	.uleb128 0x11; .uleb128 1
	.uleb128 0x12; .uleb128 6
	.uleb128 0x49; .uleb128 0x13
	.uleb128 0x7a; .uleb128 0x19 /* call_all_calls */
	.byte 0,0
	.uleb128 4; .uleb128 0x34; .byte 0
	.uleb128 3; .uleb128 8
	.uleb128 0x49; .uleb128 0x13
	.uleb128 2; .uleb128 0x18
	.byte 0,0
	.uleb128 5; .uleb128 0x48; .byte 1 /* call_site */
	.uleb128 0x7d; .uleb128 1 /* return_pc */
	.uleb128 0x7f; .uleb128 0x13 /* origin */
	.byte 0,0
	.uleb128 6; .uleb128 0x49; .byte 0 /* call_site_parameter */
	.uleb128 2; .uleb128 0x18
	.uleb128 0x7e; .uleb128 0x18 /* call_value */
	.byte 0,0
	.uleb128 7; .uleb128 0x49; .byte 0
	.uleb128 2; .uleb128 0x18
	.uleb128 0x7e; .uleb128 0x18
	.uleb128 0x86; .uleb128 0x18 /* call_data_value */
	.byte 0,0
	.uleb128 8; .uleb128 0x36; .byte 0 /* dwarf_procedure */
	.uleb128 2; .uleb128 0x18
	.byte 0,0,0
	.section .debug_info,"",%progbits
.Lcu:
#ifdef DW64
	.long 0xffffffff
	.quad .Lcu_end-.Lheader
#else
	.long .Lcu_end-.Lheader
#endif
.Lheader:
	.short 5
	.byte 1,8
	OFFSET .Labbrev
	.uleb128 1
	.asciz "dwarf-entry-value.S"
	.short 0xc
	.quad main
	.long .Lprobe_end-main
.Lint:
	.uleb128 2
	.asciz "int"
	.byte 4,5
.Lfloat:
	.uleb128 2
	.asciz "float"
	.byte 4,4
.Lwide:
	.uleb128 2
	.asciz "unsigned __int128"
	.byte 16,7
	.uleb128 3
	.asciz "main"
	.quad main
	.long .Lmain_end-main
	.long .Lint-.Lcu
	.uleb128 5
	.quad .Lreturn
	.long .Lprobe-.Lcu
	.uleb128 6
	.uleb128 1; .byte 0x50 /* reg0 */
	.uleb128 2; .byte 0x83,1 /* caller breg19 + 1 = 40 */
	.uleb128 6
	.uleb128 1; .byte 0x51
	.uleb128 1; .byte 0x32 /* lit2 */
	.uleb128 7
	.uleb128 1; .byte 0x52
	.uleb128 9; .byte 3; .quad entry_cell
	.uleb128 2; .byte 0x10,42
	.uleb128 6
	.uleb128 1; .byte 0x54 /* reg4 has 42.5f bits */
	.uleb128 8f-7f
7:
	.byte 0xa4; .uleb128 .Lfloat-.Lcu; .byte 4; .long 0x422a0000
8:
	.uleb128 6
	.uleb128 2; .byte 0x90,64 /* regx64: AArch64 SIMD v0 */
	.uleb128 8f-7f
7:
	.byte 0xa4; .uleb128 .Lwide-.Lcu; .byte 16; .quad 7,42
8:
	.byte 0,0
.Lprobe:

	.uleb128 3
	.asciz "entry_probe"
	.quad entry_probe
	.long .Lprobe_end-entry_probe
	.long .Lint-.Lcu
	.macro var name
	.uleb128 4
	.asciz "\name"
	.long .Lint-.Lcu
	.uleb128 2f-1f
1:
	.endm
	.macro endvar
	.byte 0x9f
2:
	.endm
	.macro entry
	.byte 0xa3
	.uleb128 4f-3f
3:
	.endm
	.macro endentry
4:
	.endm
	var constant
	entry
	.byte 0x10,42
	endentry
	endvar
	var gnu_entry
	.byte 0xf3,2,0x10,42
	endvar
	var branch
	entry
	.byte 0x31,0x28,5,0,0x10,99,0x2f,2,0,0x10,42
	endentry
	endvar
	var arithmetic
	entry
	.byte 0x10,20,0x32,0x1e,0x23,2
	endentry
	endvar
	var nested
	entry
	.byte 0xa3,2,0x10,40,0x23,2
	endentry
	endvar
	var isolated
	.byte 0x32
	entry
	.byte 0x10,40
	endentry
	.byte 0x22
	endvar
	var reg_value
	entry
	.byte 0x50
	endentry
	endvar
	var breg_value
	entry
	.byte 0x70,2
	endentry
	endvar
	var bregx_value
	entry
	.byte 0x92,0,2
	endentry
	endvar
	var registers
	entry
	.byte 0x70,0,0x71,0,0x22
	endentry
	endvar
	var nested_register
	entry
	.byte 0xa3,2,0x70,0,0x23,2
	endentry
	endvar
	var restored_context
	entry
	.byte 0x70,0
	endentry
	.byte 0x70,0,0x22
	endvar
	var data_value
	entry
	.byte 0x72,0,0x94,4
	endentry
	endvar
	var typed_float
	entry
	.byte 0xa5,4; .uleb128 .Lfloat-.Lcu
	endentry
	.byte 0xa8; .uleb128 .Lint-.Lcu
	endvar
	var typed_wide
	entry
	.byte 0xa5,64; .uleb128 .Lwide-.Lcu
	.byte 0xa4; .uleb128 .Lwide-.Lcu; .byte 16; .quad 0,1
	.byte 0x1b /* unsigned 128-bit division by 2^64 */
	endentry
	.byte 0xa8; .uleb128 .Lint-.Lcu
	endvar
	var memory_value
	entry
	.byte 3; .quad entry_cell
	.byte 0x94,4
	endentry
	endvar
	var missing_register
	entry
	.byte 0x73,0
	endentry
	endvar
	var frame_base
	entry
	.byte 0x91,0
	endentry
	endvar
	var cfa_value
	entry
	.byte 0x9c
	endentry
	endvar
	var procedure
	entry
	.byte 0x99; .long .Lproc-.Lcu
	endentry
	endvar
	var empty
	entry
	endentry
	endvar
	var two_values
	entry
	.byte 0x31,0x32
	endentry
	endvar
	var borrowed_stack
	.byte 0x10,42
	entry
	.byte 0x13
	endentry
	endvar
	var truncated_block
	.byte 0xa3,127,0x31
	endvar
	var overflowing_length
	.byte 0xa3,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,1
	endvar
	var truncated_type
	entry
	.byte 0xa4; .uleb128 .Lint-.Lcu; .byte 4,1
	endentry
	endvar
	var truncated_leb
	entry
	.byte 0x10,0x80
	endentry
	endvar
	var truncated_fixed
	entry
	.byte 0x0e,1
	endentry
	endvar
	var bad_branch
	entry
	.byte 0x2f,0xff,0x7f
	endentry
	endvar
	var pieces
	entry
	.byte 0x31,0x93,4
	endentry
	endvar
	var recursive
	entry
	.byte 0x99; .long .Lrecursive-.Lcu
	endentry
	endvar
	var object_address
	entry
	.byte 0x97
	endentry
	endvar
	.byte 0
.Lproc:
	.uleb128 8
	.uleb128 4
	.byte 0x70,0,0x23,2
.Lrecursive:
	.uleb128 8
	.uleb128 7
	.byte 0xa3,5,0x99; .long .Lrecursive-.Lcu
	.byte 0
.Lcu_end:
	.section .note.GNU-stack,"",%progbits
