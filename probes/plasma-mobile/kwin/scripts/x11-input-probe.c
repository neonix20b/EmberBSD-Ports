/* SPDX-License-Identifier: MIT */
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    Display *display;
    const char *text = "emberbsd";
    int event_base, error_base, major, minor;
    Window root, parent, *children = NULL, target = None;
    unsigned int count, i, matches = 0;

    if (argc != 2 || (display = XOpenDisplay(argv[1])) == NULL)
        return 1;
    if (!XTestQueryExtension(display, &event_base, &error_base, &major, &minor))
        return 2;
    root = DefaultRootWindow(display);
    if (!XQueryTree(display, root, &root, &parent, &children, &count))
        return 4;
    for (i = 0; i < count; i++) {
        XWindowAttributes attributes;
        if (XGetWindowAttributes(display, children[i], &attributes) &&
            attributes.map_state == IsViewable && attributes.width >= 640 &&
            attributes.height >= 480) {
            target = children[i];
            matches++;
        }
    }
    XFree(children);
    /* The dedicated X server must contain exactly one compositor window. */
    if (matches != 1)
        return 5;
    XSetInputFocus(display, target, RevertToParent, CurrentTime);
    XTestFakeMotionEvent(display, DefaultScreen(display), 400, 300, 20);
    for (; *text != '\0'; text++) {
        char name[2] = { *text, '\0' };
        KeyCode code = XKeysymToKeycode(display, XStringToKeysym(name));
        if (code == 0)
            return 3;
        XTestFakeKeyEvent(display, code, True, 20);
        XTestFakeKeyEvent(display, code, False, 20);
    }
    XSync(display, False);
    XCloseDisplay(display);
    return 0;
}
