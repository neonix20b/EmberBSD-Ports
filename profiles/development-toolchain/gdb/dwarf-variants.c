/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted), bounded DWARF consumer acceptance. */
struct variant_record { long id; unsigned int flags; };
struct variant_record variant_global = { 40, 7 };
extern void variant_touch(int *);

__attribute__((noinline, noipa)) static int
variant_checkpoint(int seed)
{
	struct variant_record record = { seed, 7 };
	int local = seed + 1;
	int tracked = seed + 2;

	__asm__ volatile (".global variant_stop_one\nvariant_stop_one:\nnop"
	    : : "r"(tracked), "r"(record.id), "r"(record.flags) : "memory");
	variant_touch(&local);
	tracked += local;
	__asm__ volatile (".global variant_stop_two\nvariant_stop_two:\nnop"
	    : : "r"(tracked), "r"(record.id), "r"(record.flags) : "memory");
	return local == 44 && tracked == 86 && record.id == 40;
}

int
main(void)
{
	return variant_checkpoint(variant_global.id) ? 0 : 1;
}
