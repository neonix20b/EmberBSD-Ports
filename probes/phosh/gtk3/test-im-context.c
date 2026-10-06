/* Verify that the installed GTK3 input cache selects its real Wayland module. */
#include <gtk/gtk.h>

int
main(int argc, char **argv)
{
	GtkIMContext *context;
	const char *id;
	int status;

	if (!gtk_init_check(&argc, &argv))
	    return 77;
	context = gtk_im_multicontext_new();
	gtk_im_context_focus_in(context);
	id = gtk_im_multicontext_get_context_id(GTK_IM_MULTICONTEXT(context));
	g_print("GTK3 input context: %s\n", id != NULL ? id : "(none)");
	status = g_strcmp0(id, "wayland") == 0 ? 0 : 1;
	gtk_im_context_focus_out(context);
	g_object_unref(context);
	return status;
}
