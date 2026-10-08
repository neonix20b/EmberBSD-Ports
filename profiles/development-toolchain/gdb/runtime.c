/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted), actual native debugger contract. */
#include <signal.h>
#include <stdint.h>
#include <wchar.h>

struct debugger_record { long id; unsigned int flags; };
struct debugger_record debugger_data = { 40, 7 };
wchar_t debugger_wide[] = L"caf\u00e9";
static volatile sig_atomic_t handled;

static void
handler(int signo)
{
	uint64_t zero = 0;

	__asm__ volatile ("msr fpcr, %0; msr fpsr, %0" :: "r"(zero));
	handled = signo;
	__asm__ volatile ("" ::: "memory"); /* DEBUGGER_SIGNAL */
}

__attribute__((noinline)) static int
checkpoint(int seed)
{

	volatile int local = seed + 1;
	__asm__ volatile ("" ::: "memory");
	return local; /* DEBUGGER_STOP */
}

int
main(void)
{
	uint64_t fpcr = 0x1000000, fpsr = 0x10;
	int result;

	/* The debugger changes local from 41 to 42 before continuing. */
	__asm__ volatile ("msr fpcr, %0; msr fpsr, %1" :: "r"(fpcr), "r"(fpsr));
	result = checkpoint(debugger_data.id);
	__asm__ volatile ("mrs %0, fpcr; mrs %1, fpsr" : "=r"(fpcr), "=r"(fpsr));
	if (result != 42 || fpcr != 0 || fpsr != 0)
		return 1;
	fpcr = 0x400000;
	fpsr = 8;
	__asm__ volatile ("msr fpcr, %0; msr fpsr, %1" :: "r"(fpcr), "r"(fpsr));
	if (signal(SIGUSR1, handler) == SIG_ERR || raise(SIGUSR1) != 0)
		return 2;
	__asm__ volatile ("mrs %0, fpcr; mrs %1, fpsr" : "=r"(fpcr), "=r"(fpsr));
	return handled == SIGUSR1 && fpcr == 0x400000 && fpsr == 8 ? 0 : 3;
}
