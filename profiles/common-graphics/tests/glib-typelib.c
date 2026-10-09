/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted). Load packaged metadata with target GLib. */
#include <girepository/girepository.h>
#include <stdio.h>
#include <string.h>

#include "typelibs.h"

int
main(void)
{
	GIRepository *repository;
	GIBaseInfo *info;
	GITypelib *typelib;
	GBytes *bytes;
	GError *error = NULL;
	GIArgument result, extra = { 0 };
	const char *name;
	unsigned int cycle, i, count;
	gint64 before, after;
	const unsigned char invalid[16] = { 0 };

	bytes = g_bytes_new_static(invalid, sizeof(invalid));
	typelib = gi_typelib_new_from_bytes(bytes, &error);
	g_bytes_unref(bytes);
	if (typelib != NULL || error == NULL) {
		fprintf(stderr, "invalid typelib was accepted\n");
		return 1;
	}
	g_clear_error(&error);
	for (cycle = 0; cycle < 4; cycle++) {
		repository = gi_repository_new();
		for (i = 0; i < G_N_ELEMENTS(fixtures); i++) {
			bytes = g_bytes_new_static(fixtures[i].start,
			    fixtures[i].end - fixtures[i].start);
			typelib = gi_typelib_new_from_bytes(bytes, &error);
			g_bytes_unref(bytes);
			if (typelib == NULL) {
				fprintf(stderr, "typelib %s: %s\n",
				    fixtures[i].name, error->message);
				return 1;
			}
			name = gi_repository_load_typelib(repository, typelib,
			    GI_REPOSITORY_LOAD_FLAG_LAZY, &error);
			if (name == NULL || strcmp(name, fixtures[i].name) != 0 ||
			    !gi_repository_is_registered(repository, name,
			    fixtures[i].version)) {
				fprintf(stderr, "namespace %s failed\n", fixtures[i].name);
				return 1;
			}
			count = gi_repository_get_n_infos(repository, name);
			info = gi_repository_find_by_name(repository, name,
			    fixtures[i].lookup);
			if (count == 0 || info == NULL ||
			    strcmp(gi_base_info_get_namespace(info), name) != 0) {
				fprintf(stderr, "metadata lookup %s failed\n", name);
				return 1;
			}
			gi_base_info_unref(info);
			gi_typelib_unref(typelib);
			printf("cycle %u: %s %u infos\n", cycle + 1, name, count);
		}
		info = gi_repository_find_by_name(repository, "GLib",
		    "get_monotonic_time");
		if (info == NULL || !GI_IS_FUNCTION_INFO(info) ||
		    strcmp(gi_function_info_get_symbol(GI_FUNCTION_INFO(info)),
		    "g_get_monotonic_time") != 0)
			return 1;
		before = g_get_monotonic_time();
		if (!gi_function_info_invoke(GI_FUNCTION_INFO(info), NULL, 0,
		    NULL, 0, &result, &error)) {
			fprintf(stderr, "invoke failed: %s\n", error->message);
			return 1;
		}
		after = g_get_monotonic_time();
		if (result.v_int64 < before || result.v_int64 > after)
			return 1;
		if (gi_function_info_invoke(GI_FUNCTION_INFO(info), &extra, 1,
		    NULL, 0, &result, &error) || !g_error_matches(error,
		    GI_INVOKE_ERROR, GI_INVOKE_ERROR_ARGUMENT_MISMATCH))
			return 1;
		g_clear_error(&error);
		gi_base_info_unref(info);
		g_object_unref(repository);
	}
	puts("PASS: seven packaged namespaces, four target invoke lifecycles, invalid data/signature refused");
	return 0;
}
