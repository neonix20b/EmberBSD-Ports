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

static void
send_key(KeySym symbol, int shifted)
{
	KeyCode code, shift;

	code = XKeysymToKeycode(display, symbol);
	shift = XKeysymToKeycode(display, XK_Shift_L);
	if (code == 0 || (shifted && shift == 0)) {
		fputs("Key is not mapped\n", stderr);
		exit(1);
	}
	if (shifted)
		XTestFakeKeyEvent(display, shift, True, CurrentTime);
	XTestFakeKeyEvent(display, code, True, CurrentTime);
	XTestFakeKeyEvent(display, code, False, CurrentTime);
	if (shifted)
		XTestFakeKeyEvent(display, shift, False, CurrentTime);
	XSync(display, False);
}

int
main(int argc, char **argv)
{
	Window window = None, focus;
	int attempt, revert, event_base, error_base, major, minor;
	int shifted, min, max, per, index;
	XEvent event;
	KeySym symbol, *map;
	const unsigned char *text;

	if (argc != 4 || (strcmp(argv[2], "text") != 0 &&
	    strcmp(argv[2], "key") != 0))
		return 2;
	display = XOpenDisplay(NULL);
	if (display == NULL || !XTestQueryExtension(display, &event_base,
	    &error_base, &major, &minor))
		return 1;
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
		if (focus == window)
			break;
		pause_poll();
	}
	if (attempt == 50) {
		fputs("WM did not focus target\n", stderr);
		return 1;
	}
	if (strcmp(argv[2], "key") == 0) {
		symbol = XStringToKeysym(argv[3]);
		if (symbol == NoSymbol)
			return 2;
		send_key(symbol, 0);
	} else {
		for (text = (unsigned char *)argv[3]; *text != '\0'; text++) {
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
			send_key(symbol, shifted);
		}
	}
	XCloseDisplay(display);
	return 0;
}
