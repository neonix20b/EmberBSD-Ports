/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted), bounded indexed-string operand regression. */
	.section .debug_info.dwo,"e",%progbits
#ifdef DW64
	.long 0xffffffff
	.quad .Lend-.Lunit
#else
	.long .Lend-.Lunit
#endif
.Lunit:
	.short 5
	.byte 5, 8
#ifdef DW64
	.quad 0
#else
	.long 0
#endif
	.quad 0x1122334455667788
	.uleb128 1
#ifdef TRUNCATED
	.byte 0x80
#else
	.byte 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,1
#endif
.Lend:
	.section .debug_abbrev.dwo,"e",%progbits
	.uleb128 1
	.uleb128 0x11
	.byte 0
	.uleb128 3
	.uleb128 0x1a
	.byte 0,0,0
	.section .debug_str_offsets.dwo,"e",%progbits
#ifdef DW64
	.long 0xffffffff
	.quad 12
	.short 5,0
	.quad 0
#else
	.long 8
	.short 5,0
	.long 0
#endif
	.section .debug_str.dwo,"e",%progbits
	.asciz "bounded-string"
