/* Exercise the actual window manager through standard X11/EWMH requests. */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static Display *display;
static Window root;

static void
pause_poll(void)
{
	struct timespec delay = { 0, 100000000 };
	nanosleep(&delay, NULL);
}

static unsigned long *
property(Window window, const char *name, Atom requested, unsigned long *count)
{
	Atom actual;
	int format;
	unsigned long remaining;
	unsigned char *data = NULL;

	*count = 0;
	if (XGetWindowProperty(display, window, XInternAtom(display, name, False),
	    0, 4096, False, requested, &actual, &format, count, &remaining,
	    &data) != Success || actual != requested || format != 32) {
		if (data != NULL)
			XFree(data);
		*count = 0;
		return NULL;
	}
	return (unsigned long *)data;
}

static int
contains(Window window, const char *name, Atom type, unsigned long value)
{
	unsigned long count, i, *values;
	int found = 0;

	values = property(window, name, type, &count);
	for (i = 0; i < count; i++)
		if (values[i] == value)
			found = 1;
	if (values != NULL)
		XFree(values);
	return found;
}

static void
expect(int condition, const char *message)
{
	if (!condition) {
		fprintf(stderr, "FAIL: %s\n", message);
		exit(1);
	}
	printf("PASS: %s\n", message);
}

static void
wait_property(Window window, const char *name, Atom type,
    unsigned long value, int present)
{
	int attempt;

	for (attempt = 0; attempt < 150; attempt++) {
		if (contains(window, name, type, value) == present)
			return;
		pause_poll();
	}
	fprintf(stderr, "FAIL: timed out waiting for %s (%s)\n", name,
	    present ? "present" : "absent");
	exit(1);
}

static void
fullscreen(Window window, Atom state, int enable)
{
	XEvent event;

	memset(&event, 0, sizeof(event));
	event.xclient.type = ClientMessage;
	event.xclient.window = window;
	event.xclient.message_type = XInternAtom(display, "_NET_WM_STATE", False);
	event.xclient.format = 32;
	event.xclient.data.l[0] = enable;
	event.xclient.data.l[1] = state;
	event.xclient.data.l[3] = 1;
	XSendEvent(display, root, False,
	    SubstructureRedirectMask | SubstructureNotifyMask, &event);
	XFlush(display);
	wait_property(window, "_NET_WM_STATE", XA_ATOM, state, enable);
}

int
main(void)
{
	Window owner = None, window, child;
	Atom full, actual;
	unsigned long count, remaining, *check;
	unsigned char *name = NULL;
	int attempt, format, x, y;
	XWindowAttributes attributes;

	display = XOpenDisplay(NULL);
	expect(display != NULL, "connected to the isolated X server");
	root = DefaultRootWindow(display);
	for (attempt = 0; attempt < 150; attempt++) {
		owner = XGetSelectionOwner(display, XInternAtom(display, "WM_S0", False));
		if (owner != None)
			break;
		pause_poll();
	}
	expect(owner != None, "WM_S0 selection has an owner");
	wait_property(root, "_NET_SUPPORTING_WM_CHECK", XA_WINDOW, owner, 1);
	check = property(root, "_NET_SUPPORTING_WM_CHECK", XA_WINDOW, &count);
	expect(count == 1 && check[0] == owner, "root identifies the actual WM owner");
	XFree(check);
	expect(contains(owner, "_NET_SUPPORTING_WM_CHECK", XA_WINDOW, owner),
	    "supporting WM window self-references");
	XGetWindowProperty(display, owner, XInternAtom(display, "_NET_WM_NAME", False),
	    0, 128, False, XInternAtom(display, "UTF8_STRING", False), &actual,
	    &format, &count, &remaining, &name);
	expect(name != NULL && count == strlen("Enlightenment") &&
	    memcmp(name, "Enlightenment", count) == 0, "window manager is Enlightenment");
	XFree(name);

	window = XCreateSimpleWindow(display, root, 80, 80, 320, 200, 0,
	    BlackPixel(display, 0), WhitePixel(display, 0));
	XStoreName(display, window, "EmberBSD Enlightenment contract");
	XMapWindow(display, window);
	XFlush(display);
	wait_property(root, "_NET_CLIENT_LIST", XA_WINDOW, window, 1);
	wait_property(window, "WM_STATE", XInternAtom(display, "WM_STATE", False),
	    NormalState, 1);
	expect(XGetWindowAttributes(display, window, &attributes) &&
	    attributes.map_state == IsViewable, "client is managed and visible");
	full = XInternAtom(display, "_NET_WM_STATE_FULLSCREEN", False);
	fullscreen(window, full, 1);
	for (attempt = 0; attempt < 150; attempt++) {
		XGetWindowAttributes(display, window, &attributes);
		XTranslateCoordinates(display, window, root, 0, 0, &x, &y, &child);
		if (x == 0 && y == 0 && attributes.width == DisplayWidth(display, 0) &&
		    attributes.height == DisplayHeight(display, 0))
			break;
		pause_poll();
	}
	expect(attempt < 150, "fullscreen request changes actual client geometry");
	fullscreen(window, full, 0);
	for (attempt = 0; attempt < 150; attempt++) {
		XGetWindowAttributes(display, window, &attributes);
		if (attributes.width == 320 && attributes.height == 200)
			break;
		pause_poll();
	}
	expect(attempt < 150, "leaving fullscreen restores the client size");
	XDestroyWindow(display, window);
	XFlush(display);
	wait_property(root, "_NET_CLIENT_LIST", XA_WINDOW, window, 0);
	puts("PASS: destroyed client leaves the managed window list");
	XCloseDisplay(display);
	return 0;
}
