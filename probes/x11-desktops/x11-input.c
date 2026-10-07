/* SPDX-License-Identifier: BSD-2-Clause */
/* Deliver XTEST keyboard input to a named, focused application. */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static Display *display;

static void
pause_poll(void)
{
	struct timespec delay = { 0, 100000000 };

	nanosleep(&delay, NULL);
}

static Window
find_window(Window window, const char *title, unsigned int depth)
{
	Window root, parent, *children = NULL, found = None;
	unsigned int count = 0, i;
	char *name = NULL;

	if (XFetchName(display, window, &name) && name != NULL) {
		if (strcmp(name, title) == 0)
			found = window;
		XFree(name);
	}
	if (found != None || depth > 8)
		return found;
	if (XQueryTree(display, window, &root, &parent, &children, &count)) {
		for (i = 0; i < count && found == None; i++)
			found = find_window(children[i], title, depth + 1);
	}
	if (children != NULL)
		XFree(children);
	return found;
}

/* GTK focuses an input-only child of its managed top-level window. */
static int
focus_belongs_to(Window focus, Window target)
{
	Window root, parent, *children = NULL;
	unsigned int count;
	int depth;

	for (depth = 0; depth < 64 && focus != None && focus != PointerRoot; depth++) {
		if (focus == target)
			return 1;
		if (!XQueryTree(display, focus, &root, &parent, &children, &count))
			return 0;
		if (children != NULL)
			XFree(children);
		focus = parent;
	}
	return 0;
}

static void
send_key(KeySym symbol, int shifted, KeySym modifier)
{
	KeyCode code, shift, modifier_code = 0;

	code = XKeysymToKeycode(display, symbol);
	shift = XKeysymToKeycode(display, XK_Shift_L);
	if (modifier != NoSymbol)
		modifier_code = XKeysymToKeycode(display, modifier);
	if (code == 0 || (shifted && shift == 0) ||
	    (modifier != NoSymbol && modifier_code == 0)) {
		fputs("Key is not mapped\n", stderr);
		exit(1);
	}
	if (modifier_code != 0)
		XTestFakeKeyEvent(display, modifier_code, True, CurrentTime);
	if (shifted)
		XTestFakeKeyEvent(display, shift, True, CurrentTime);
	XTestFakeKeyEvent(display, code, True, CurrentTime);
	XTestFakeKeyEvent(display, code, False, CurrentTime);
	if (shifted)
		XTestFakeKeyEvent(display, shift, False, CurrentTime);
	if (modifier_code != 0)
		XTestFakeKeyEvent(display, modifier_code, False, CurrentTime);
	XSync(display, False);
}

int
main(int argc, char **argv)
{
	Window window = None, focus;
	int attempt, revert, event_base, error_base, major, minor;
	int shifted, min, max, per, index;
	XEvent event;
	KeySym symbol, *map, modifier = NoSymbol;
	const unsigned char *text;

	if (argc < 3 || argc > 5)
		return 2;
	if (!((argc == 3 && strcmp(argv[2], "focus") == 0) ||
	    (argc == 4 && strcmp(argv[2], "text") == 0) ||
	    (argc >= 4 && strcmp(argv[2], "key") == 0)))
		return 2;
	if (argc == 5) {
		modifier = XStringToKeysym(argv[3]);
		if (modifier != XK_Control_L && modifier != XK_Alt_L &&
		    modifier != XK_Shift_L && modifier != XK_Super_L)
			return 2;
	}
	display = XOpenDisplay(NULL);
	if (display == NULL || !XTestQueryExtension(display, &event_base,
	    &error_base, &major, &minor))
		return 1;
	/* GTK popup menus own a keyboard grab, not an EWMH-managed window. */
	if (strcmp(argv[1], "--current") == 0 && strcmp(argv[2], "key") == 0)
		goto input;
	for (attempt = 0; attempt < 100 && window == None; attempt++) {
		window = find_window(DefaultRootWindow(display), argv[1], 0);
		if (window == None)
			pause_poll();
	}
	if (window == None) {
		fputs("Named window missing\n", stderr);
		return 1;
	}
	memset(&event, 0, sizeof(event));
	event.xclient.type = ClientMessage;
	event.xclient.window = window;
	event.xclient.message_type = XInternAtom(display,
	    "_NET_ACTIVE_WINDOW", False);
	event.xclient.format = 32;
	event.xclient.data.l[0] = 2;
	XSendEvent(display, DefaultRootWindow(display), False,
	    SubstructureRedirectMask | SubstructureNotifyMask, &event);
	XFlush(display);
	for (attempt = 0; attempt < 50; attempt++) {
		XGetInputFocus(display, &focus, &revert);
		if (focus_belongs_to(focus, window))
			break;
		pause_poll();
	}
	if (attempt == 50) {
		fprintf(stderr, "WM did not focus target 0x%lx; actual focus 0x%lx\n",
		    window, focus);
		for (attempt = 0; attempt < 8 && focus != None &&
		    focus != PointerRoot; attempt++) {
			Window root, parent, *children = NULL;
			unsigned int count;
			if (!XQueryTree(display, focus, &root, &parent, &children, &count))
				break;
			if (children != NULL)
				XFree(children);
			fprintf(stderr, "Focus ancestor: 0x%lx\n", parent);
			focus = parent;
		}
		return 1;
	}
input:
	if (strcmp(argv[2], "focus") == 0) {
		XCloseDisplay(display);
		return 0;
	}
	if (strcmp(argv[2], "key") == 0) {
		symbol = XStringToKeysym(argv[argc - 1]);
		if (symbol == NoSymbol)
			return 2;
		send_key(symbol, 0, modifier);
	} else {
		for (text = (unsigned char *)argv[3]; *text != '\0'; text++) {
			XGetInputFocus(display, &focus, &revert);
			if (!focus_belongs_to(focus, window)) {
				fputs("Target lost focus during text input\n", stderr);
				return 1;
			}
			symbol = *text;
			shifted = 0;
			if (*text < 32 || *text > 126) {
				fputs("Only printable ASCII text is supported\n",
				    stderr);
				return 2;
			}
			XDisplayKeycodes(display, &min, &max);
			map = XGetKeyboardMapping(display, min, max - min + 1,
			    &per);
			if (map == NULL)
				return 1;
			for (index = 0; index < max - min + 1; index++) {
				if (map[index * per] == symbol)
					break;
				if (per > 1 && map[index * per + 1] == symbol) {
					shifted = 1;
					break;
				}
			}
			XFree(map);
			if (index == max - min + 1)
				return 1;
			send_key(symbol, shifted, NoSymbol);
		}
	}
	XCloseDisplay(display);
	return 0;
}
