/* SPDX-License-Identifier: MIT */
#include <apriltag/common/getopt.h>
#include <apriltag/common/string_util.h>
#include <locale.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "ctype regression failed: %s\n", #condition); return 1; \
} } while (0)

int
main(void)
{
    CHECK(setlocale(LC_CTYPE, "C") != NULL);
    CHECK(strcaseeq("Tag", "tAG"));
    CHECK(!strcaseeq("Tag", "ta"));
    for (unsigned byte = 128; byte <= 255; ++byte) {
        char first[] = { (char)byte, '\0' };
        char other[] = { (char)(byte == 255 ? 128 : byte + 1), '\0' };
        char padded[] = { ' ', '\t', (char)byte, ' ', '\n', '\0' };
        CHECK(strcaseeq(first, first));
        CHECK(!strcaseeq(first, other));
        CHECK(str_trim(padded) == padded);
        CHECK(padded[0] == (char)byte && padded[1] == '\0');
        getopt_t *options = getopt_create();
        CHECK(options != NULL);
        char name[] = "contract";
        char option[] = { '-', (char)byte, '\0' };
        char *argv[] = { name, option };
        CHECK(getopt_parse(options, 2, argv, 0) == 0);
        getopt_destroy(options);
    }
    getopt_t *options = getopt_create();
    CHECK(options != NULL);
    char name[] = "contract", negative[] = "-12";
    char *argv[] = { name, negative };
    CHECK(getopt_parse(options, 2, argv, 0) == 1);
    const zarray_t *extra = getopt_get_extra_args(options);
    CHECK(zarray_size(extra) == 1);
    char *value;
    zarray_get(extra, 0, &value);
    CHECK(strcmp(value, "-12") == 0);
    getopt_destroy(options);
    puts("AprilTag ctype: ASCII case, all 128 high bytes, trimming and negative number passed");
    return 0;
}
