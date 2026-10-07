/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD; AI-assisted host metadata boundary, not pkg_admin. */
#include <fnmatch.h>
#include <stdio.h>
#include <string.h>
#include "dewey.h"
int main(int argc, char **argv)
{
    if (argc == 4 && strcmp(argv[1], "pmatch") == 0) {
        if (strpbrk(argv[2], "<>"))
            return dewey_match(argv[2], argv[3]) == 1 ? 0 : 1;
        return fnmatch(argv[2], argv[3], 0) == 0 ? 0 : 1;
    }
    /* Package DB/config queries have no installed host target metadata. */
    if (argc >= 2 && (strcmp(argv[1], "config-var") == 0 ||
        strcmp(argv[1], "-K") == 0))
        return 0;
    return 1;
}
