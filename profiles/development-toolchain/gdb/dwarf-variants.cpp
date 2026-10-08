/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted), C++ types and optimized local acceptance. */
struct VariantBase { long id; };
template<class T> struct VariantRecord : VariantBase { T flags; };
VariantRecord<unsigned> variant_cpp_global = { { 40 }, 7 };

__attribute__((noinline, noipa)) static int
variant_cpp_checkpoint(int seed)
{
	VariantRecord<unsigned> record = { { seed }, 7 };
	int tracked = seed + 2;

	__asm__ volatile (".global variant_cpp_stop\nvariant_cpp_stop:\nnop"
	    : : "r"(tracked), "r"(record.id), "r"(record.flags) : "memory");
	return tracked == 42 && record.id == 40 && record.flags == 7;
}

int
main()
{
	return variant_cpp_checkpoint(variant_cpp_global.id) ? 0 : 1;
}
