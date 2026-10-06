/*
 * SPDX-License-Identifier: BSD-2-Clause
 * Build only awesome 4.3's 19x19 Zenburn PNG variants with GdkPixbuf.
 * Preserve the upstream build's linear RGB/gamma/alpha and grayscale steps.
 */
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static guchar
quantize(double value)
{
	return (guchar)floor(fmin(255.0, fmax(0.0, value)) + 0.5);
}

static guchar
normal_channel(guchar value)
{
	double linear, channel = value / 255.0;

	linear = channel <= 0.04045 ? channel / 12.92 :
	    pow((channel + 0.055) / 1.055, 2.4);
	return quantize(255.0 * pow(linear, 1.0 / 0.6));
}

int
main(int argc, char **argv)
{
	GError *error = NULL;
	GdkPixbuf *input, *output;
	GChecksum *checksum;
	guchar *pixels, *pixel;
	int normal, stride, x, y;
	gboolean saved;

	if (argc != 4 || (strcmp(argv[1], "normal") != 0 &&
	    strcmp(argv[1], "inactive") != 0)) {
		fprintf(stderr, "Usage: theme-icon normal|inactive INPUT OUTPUT\n");
		return 2;
	}
	normal = strcmp(argv[1], "normal") == 0;
	input = gdk_pixbuf_new_from_file(argv[2], &error);
	if (input == NULL) {
		fprintf(stderr, "Icon load failed: %s\n", error->message);
		g_error_free(error);
		return 1;
	}
	if (gdk_pixbuf_get_width(input) != 19 ||
	    gdk_pixbuf_get_height(input) != 19 ||
	    gdk_pixbuf_get_bits_per_sample(input) != 8 ||
	    gdk_pixbuf_get_colorspace(input) != GDK_COLORSPACE_RGB) {
		fprintf(stderr, "Expected a 19x19 8-bit Zenburn RGB icon\n");
		g_object_unref(input);
		return 1;
	}
	output = gdk_pixbuf_add_alpha(input, FALSE, 0, 0, 0);
	g_object_unref(input);
	if (output == NULL)
		return 1;
	pixels = gdk_pixbuf_get_pixels(output);
	stride = gdk_pixbuf_get_rowstride(output);
	for (y = 0; y < 19; y++) {
		for (x = 0; x < 19; x++) {
			pixel = pixels + y * stride + 4 * x;
			if (normal) {
				pixel[0] = normal_channel(pixel[0]);
				pixel[1] = normal_channel(pixel[1]);
				pixel[2] = normal_channel(pixel[2]);
				pixel[3] = quantize(pixel[3] * 0.4);
			} else {
				guchar gray = quantize(0.212656 * pixel[0] +
				    0.715158 * pixel[1] + 0.072186 * pixel[2]);
				pixel[0] = pixel[1] = pixel[2] = gray;
			}
		}
	}
	checksum = g_checksum_new(G_CHECKSUM_SHA256);
	for (y = 0; y < 19; y++)
		g_checksum_update(checksum, pixels + y * stride, 19 * 4);
	saved = gdk_pixbuf_save(output, argv[3], "png", &error, NULL);
	g_object_unref(output);
	if (!saved) {
		fprintf(stderr, "Icon save failed: %s\n", error->message);
		g_error_free(error);
		g_checksum_free(checksum);
		return 1;
	}
	puts(g_checksum_get_string(checksum));
	g_checksum_free(checksum);
	return 0;
}
