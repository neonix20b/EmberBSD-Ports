/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted), two-CU package-index consumer. */
#ifdef TYPES
struct PackageBase { long id; };
template<class T> struct PackageRecord : PackageBase { T flags; };
PackageRecord<unsigned> package_record = { { 40 }, 7 };
#else
struct PackageRecord { long id; unsigned flags; };
struct PackageRecord package_record = { 40, 7 };
#endif
extern "C" void package_touch(int *);

int
main()
{
	int value = 41;
	__asm__ volatile (".global package_stop\npackage_stop:\nnop"
	    : : "r"(value) : "memory");
	package_touch(&value);
	return value == 44 && package_record.id == 40 &&
	    package_record.flags == 7 ? 0 : 1;
}
