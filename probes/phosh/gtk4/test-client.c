/* A real GTK4/Cairo client: render before declaring success. */
#include <gtk/gtk.h>

static GtkWidget *window;
static GtkWidget *label;
static guint paints;
static gboolean changed;
static gboolean passed;

static void
painted(GdkFrameClock *clock, gpointer data)
{
	(void)clock;
	(void)data;
	paints++;
}

static gboolean
change_label(gpointer data)
{
	(void)data;
	gtk_label_set_text(GTK_LABEL(label), "The second GTK4 frame is rendered.");
	changed = TRUE;
	return G_SOURCE_REMOVE;
}

static gboolean
finish(gpointer data)
{
	GtkApplication *app = data;
	GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
	GskRenderer *renderer = gtk_native_get_renderer(GTK_NATIVE(window));
	passed = changed && paints >= 2 && GSK_IS_CAIRO_RENDERER(renderer) &&
	    gdk_surface_get_mapped(surface) &&
	    gdk_surface_get_width(surface) > 0 &&
	    gdk_surface_get_height(surface) > 0;
	g_print("%s: %u after-paint signals, mapped=%d, size=%dx%d, renderer=%s\n",
	    passed ? "PASS" : "FAIL", paints, gdk_surface_get_mapped(surface),
	    gdk_surface_get_width(surface), gdk_surface_get_height(surface),
	    G_OBJECT_TYPE_NAME(renderer));
	g_application_quit(G_APPLICATION(app));
	return G_SOURCE_REMOVE;
}

static void
activate(GtkApplication *app, gpointer data)
{
	(void)data;
	window = gtk_application_window_new(app);
	gtk_window_set_title(GTK_WINDOW(window), "GTK4 shared-memory regression");
	gtk_window_set_default_size(GTK_WINDOW(window), 317, 419);
	label = gtk_label_new("The first GTK4 frame is rendered.");
	gtk_window_set_child(GTK_WINDOW(window), label);
	gtk_window_present(GTK_WINDOW(window));
	g_signal_connect(gtk_widget_get_frame_clock(window), "after-paint",
	    G_CALLBACK(painted), NULL);
	g_timeout_add(300, change_label, NULL);
	g_timeout_add_seconds(2, finish, app);
}

int
main(int argc, char **argv)
{
	GtkApplication *app = gtk_application_new("org.emberbsd.Gtk4ShmTest",
	    G_APPLICATION_NON_UNIQUE);
	g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
	int status = g_application_run(G_APPLICATION(app), argc, argv);
	g_object_unref(app);
	return status != 0 ? status : !passed;
}
