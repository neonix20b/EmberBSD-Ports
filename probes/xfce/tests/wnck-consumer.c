/*
 * SPDX-License-Identifier: BSD-2-Clause
 * Exercise installed libwnck through its C API and report loaded DSOs.
 * AI-assisted EmberBSD verification; no display server is required.
 */
#define WNCK_I_KNOW_THIS_IS_UNSTABLE
#include <libwnck/libwnck.h>
#include <link.h>
#include <stdio.h>
#include <string.h>

static int
loaded(struct dl_phdr_info *info, size_t size, void *data)
{
	(void)size;
	(void)data;
	if (info->dlpi_name != NULL && info->dlpi_name[0] != '\0')
		printf("LOADED %s\n", info->dlpi_name);
	return (0);
}

int
main(void)
{
	GType type;

	type = wnck_application_get_type();
	if (!g_type_is_a(type, G_TYPE_OBJECT) ||
	    strcmp(g_type_name(type), "WnckApplication") != 0)
		return (1);
	printf("PASS: installed libwnck GObject type %s\n", g_type_name(type));
	dl_iterate_phdr(loaded, NULL);
	return (0);
}
