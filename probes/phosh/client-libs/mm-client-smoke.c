/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 EmberBSD contributors. AI-assisted build probe. */

#include <libmm-glib.h>

int
main(void)
{
	GError *error = NULL;
	GDBusConnection *bus;
	MMManager *manager;
	char *owner;
	int status;

	bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
	if (bus == NULL) {
		g_printerr("Cannot connect to the system bus: %s\n", error->message);
		g_error_free(error);
		return 1;
	}
	manager = mm_manager_new_sync(bus,
	    G_DBUS_OBJECT_MANAGER_CLIENT_FLAGS_DO_NOT_AUTO_START, NULL, &error);
	if (manager == NULL) {
		g_printerr("Cannot construct MMManager: %s\n", error->message);
		g_error_free(error);
		g_object_unref(bus);
		return 1;
	}
	owner = g_dbus_object_manager_client_get_name_owner(
	    G_DBUS_OBJECT_MANAGER_CLIENT(manager));
	if (owner == NULL)
		g_print("Real MMManager proxy constructed; ModemManager service is absent.\n");
	else
		g_print("ModemManager service owner: %s; modem operations not tested.\n", owner);
	status = owner == NULL ? 77 : 0;
	g_free(owner);
	g_object_unref(manager);
	g_object_unref(bus);
	return status;
}
