/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 EmberBSD contributors */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef A733_VIP_DB
typedef uint32_t vip_uint32_t;
#include "vip_feature_database.h"

int
main(void)
{
	size_t i;
	unsigned found = 0;

	for (i = 0; i < sizeof(vip_chip_info) / sizeof(vip_chip_info[0]); i++) {
		const struct _vip_hw_feature_db *db = &vip_chip_info[i];
		if (db->pid != 0x1000003b)
			continue;
		found++;
		printf("vendor PID=0x%08x revision=0x%x NN=%u TP=%u "
		    "SRAM=%u MMU_PD=%u XYDP0=%u\n", db->pid,
		    db->chip_revision, db->nn_core_count, db->tp_core_count,
		    db->vip_sram_size, db->mmu_pd_mode, db->nn_xydp0);
		if (db->chip_revision != 0x9202 || db->nn_core_count != 8 ||
		    db->tp_core_count != 0 || db->vip_sram_size != 0x80000 ||
		    !db->mmu_pd_mode || !db->nn_xydp0)
			return EXIT_FAILURE;
	}
	return found == 1 ? EXIT_SUCCESS : EXIT_FAILURE;
}
#else
typedef uint32_t gctUINT32;
typedef int gctINT;
#define gcvNULL NULL
#include "gc_feature_database.h"

int
main(void)
{
	size_t i;
	unsigned controls = 0;

	/* The original lookup executes here, including informal revision masks. */
	if (gcQueryFeatureDB(0x9000, 0x9202, 0x05090009,
	    0x08000000, 0x1000003b) != NULL) {
		fputs("A733 is now in this database; reassess the source audit.\n",
		    stderr);
		return EXIT_FAILURE;
	}
	for (i = 0; i < sizeof(gChipInfo) / sizeof(gChipInfo[0]); i++) {
		const gcsFEATURE_DATABASE *db = &gChipInfo[i];
		if (db->customerID == 0x1000003b) {
			fputs("A733 PID occurs under another identity.\n", stderr);
			return EXIT_FAILURE;
		}
		if (db->NNCoreCount == 0)
			continue;
		if (gcQueryFeatureDB(db->chipID, db->chipVersion, db->productID,
		    db->ecoID, db->customerID) == NULL) {
			fputs("Existing NPU identity lookup failed.\n", stderr);
			return EXIT_FAILURE;
		}
		controls++;
	}
	printf("Mesa A733 absent; existing NPU lookup controls=%u; entries=%zu\n",
	    controls, sizeof(gChipInfo) / sizeof(gChipInfo[0]));
	return EXIT_SUCCESS;
}
#endif
