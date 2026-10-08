/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted), validate imported debugger ABI constants. */
#define _KERNTYPES
#include <sys/types.h>
#include <stddef.h>
#include <ucontext.h>
#include <wchar.h>
#include <machine/reg.h>

_Static_assert(sizeof(struct reg) == 280, "general register set");
_Static_assert(sizeof(struct fpreg) == 528, "floating register set");
_Static_assert(offsetof(struct fpreg, fpcr) == 512, "FPCR in ptrace/core");
_Static_assert(offsetof(struct fpreg, fpsr) == 516, "FPSR in ptrace/core");
_Static_assert(offsetof(ucontext_t, uc_flags) == 0, "ucontext flags");
_Static_assert(offsetof(ucontext_t, uc_mcontext) == 64, "signal mcontext");
_Static_assert(offsetof(mcontext_t, __fregs) == 288, "signal FP vector base");
_Static_assert(_UC_FPU == 8, "signal FP validity flag");
_Static_assert(sizeof(wchar_t) == 4 && L'\u0416' == 0x416,
    "Unicode wide-character representation");

int main(void) { return 0; }
