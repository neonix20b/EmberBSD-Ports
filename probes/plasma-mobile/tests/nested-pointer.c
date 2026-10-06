/* SPDX-License-Identifier: MIT */
/* EmberBSD, AI-assisted diagnostic for a dedicated nested Mobile X server. */
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <stdio.h>
#include <stdlib.h>

static int
coordinate(const char *text, int limit)
{
    char *end;
    long value = strtol(text, &end, 10);
    if (*text == '\0' || *end != '\0' || value < 0 || value >= limit) {
        fprintf(stderr, "Invalid coordinate: %s\n", text);
        exit(2);
    }
    return (int)value;
}

int
main(int argc, char **argv)
{
    Display *display;
    Window root, parent, *children = NULL, target = None;
    unsigned int count, i, matches = 0;
    int event, error, major, minor, x0, y0, x1, y1;

    if (argc != 4 && argc != 6) {
        fprintf(stderr, "Usage: nested-pointer DISPLAY X Y [END_X END_Y]\n");
        return 2;
    }
    x0 = coordinate(argv[2], 480);
    y0 = coordinate(argv[3], 800);
    x1 = argc == 6 ? coordinate(argv[4], 480) : x0;
    y1 = argc == 6 ? coordinate(argv[5], 800) : y0;
    if ((display = XOpenDisplay(argv[1])) == NULL)
        return 1;
    if (!XTestQueryExtension(display, &event, &error, &major, &minor))
        return 3;
    root = DefaultRootWindow(display);
    if (!XQueryTree(display, root, &root, &parent, &children, &count))
        return 4;
    for (i = 0; i < count; i++) {
        XWindowAttributes a;
        if (XGetWindowAttributes(display, children[i], &a) && a.map_state == IsViewable) {
            matches++;
            if (a.width == 480 && a.height == 800 && a.x == 0 && a.y == 0)
                target = children[i];
        }
    }
    XFree(children);
    if (matches != 1 || target == None)
        return 5;
    XSetInputFocus(display, target, RevertToParent, CurrentTime);
    XTestFakeMotionEvent(display, DefaultScreen(display), x0, y0, 20);
    XTestFakeButtonEvent(display, 1, True, 20);
    for (i = 1; i <= 20; i++)
        XTestFakeMotionEvent(display, DefaultScreen(display),
            x0 + (x1 - x0) * (int)i / 20, y0 + (y1 - y0) * (int)i / 20, 15);
    XTestFakeButtonEvent(display, 1, False, 20);
    XSync(display, False);
    XCloseDisplay(display);
    return 0;
}
