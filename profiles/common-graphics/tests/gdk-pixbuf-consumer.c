/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted). Verify packaged loaders and target metadata. */
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <girepository/girepository.h>
#include <glib/gstdio.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#include "gdk-pixbuf-assets.h"

static void
append32(GByteArray *bytes, guint32 value, gboolean big)
{
	value = big ? GUINT32_TO_BE(value) : GUINT32_TO_LE(value);
	g_byte_array_append(bytes, (guint8 *)&value, 4);
}

static void
chunk(GByteArray *bytes, const char *tag, const void *data, gsize size,
    gboolean big)
{
	if (big) {
		append32(bytes, size + 8, TRUE);
		g_byte_array_append(bytes, (const guint8 *)tag, 4);
	} else {
		g_byte_array_append(bytes, (const guint8 *)tag, 4);
		append32(bytes, size, FALSE);
	}
	g_byte_array_append(bytes, data, size);
	if (!big && size % 2 != 0)
		g_byte_array_append(bytes, (const guint8 *)"\0", 1);
}

static void
decode(const char *type, const guint8 *data, gsize size, int width,
    int height, guint32 color, int tolerance)
{
	GdkPixbufLoader *loader;
	GdkPixbuf *image;
	GError *error = NULL;
	gsize offset, n;
	guchar *pixel;
	int pass, x, y, c;

	for (pass = 0; pass < 2; pass++) {
		loader = gdk_pixbuf_loader_new_with_type(type, &error);
		g_assert_no_error(error);
		for (offset = 0; offset < size; offset += n) {
			n = pass == 0 ? size : MIN((gsize)7, size - offset);
			g_assert_true(gdk_pixbuf_loader_write(loader,
			    data + offset, n, &error));
			g_assert_no_error(error);
		}
		g_assert_true(gdk_pixbuf_loader_close(loader, &error));
		g_assert_no_error(error);
		image = gdk_pixbuf_loader_get_pixbuf(loader);
		g_assert_nonnull(image);
		g_assert_cmpint(gdk_pixbuf_get_width(image), ==, width);
		g_assert_cmpint(gdk_pixbuf_get_height(image), ==, height);
		for (y = 0; y < height; y++) {
			for (x = 0; x < width; x++) {
				pixel = gdk_pixbuf_get_pixels(image) +
				    y * gdk_pixbuf_get_rowstride(image) +
				    x * gdk_pixbuf_get_n_channels(image);
				for (c = 0; c < 3; c++)
					g_assert_cmpint(ABS(pixel[c] -
					    (int)((color >> (16 - c * 8)) & 255)),
					    <=, tolerance);
			}
		}
		g_object_unref(loader);
	}
	printf("decode %s: %dx%d, full and incremental pixels PASS\n",
	    type, width, height);
}

static void
formats(void)
{
	const char *savers[] = { "png", "jpeg", "tiff", "bmp", "ico" };
	const guint8 gif[] = { 'G','I','F','8','9','a',1,0,1,0,128,0,0,
	    51,102,153,0,0,0,44,0,0,0,0,1,0,1,0,0,2,2,68,1,0,59 };
	const char *xpm = "/* XPM */\nstatic char *a[] = {\n"
	    "\"2 2 1 1\",\n\"x c #336699\",\n\"xx\",\n\"xx\"};\n";
	const char *xbm = "#define a_width 8\n#define a_height 8\n"
	    "static unsigned char a_bits[] = {\n"
	    "0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff};\n";
	guint8 tga[18] = { 0,0,2,0,0,0,0,0,0,0,0,0,16,0,16,0,24,32 };
	guint8 rgb[] = { 51,102,153 }, bgr[] = { 153,102,51 };
	guint8 icns[12], mask[256];
	GdkPixbuf *image;
	GError *error = NULL;
	GByteArray *bytes, *body, *frames, *header;
	gchar *encoded;
	gsize length;
	unsigned int i, c;

	image = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, 16, 16);
	gdk_pixbuf_fill(image, 0x336699ff);
	for (i = 0; i < G_N_ELEMENTS(savers); i++) {
		g_assert_true(gdk_pixbuf_save_to_buffer(image, &encoded,
		    &length, savers[i], &error, NULL));
		g_assert_no_error(error);
		decode(savers[i], (guint8 *)encoded, length, 16, 16,
		    0x336699, strcmp(savers[i], "jpeg") == 0 ? 3 : 0);
		if (strcmp(savers[i], "png") == 0) {
			bytes = g_byte_array_new();
			chunk(bytes, "idat", encoded, length, TRUE);
			decode("qtif", bytes->data, bytes->len, 16, 16,
			    0x336699, 0);
			g_byte_array_unref(bytes);
		}
		if (strcmp(savers[i], "ico") == 0) {
			header = g_byte_array_new();
			append32(header, 36, FALSE);
			append32(header, 1, FALSE);
			append32(header, 1, FALSE);
			append32(header, 16, FALSE);
			append32(header, 16, FALSE);
			append32(header, 32, FALSE);
			append32(header, 1, FALSE);
			append32(header, 6, FALSE);
			append32(header, 1, FALSE);
			frames = g_byte_array_new();
			g_byte_array_append(frames, (const guint8 *)"fram", 4);
			chunk(frames, "icon", encoded, length, FALSE);
			body = g_byte_array_new();
			g_byte_array_append(body, (const guint8 *)"ACON", 4);
			chunk(body, "anih", header->data, header->len, FALSE);
			chunk(body, "LIST", frames->data, frames->len, FALSE);
			bytes = g_byte_array_new();
			chunk(bytes, "RIFF", body->data, body->len, FALSE);
			decode("ani", bytes->data, bytes->len, 16, 16,
			    0x336699, 0);
			g_byte_array_unref(bytes);
			g_byte_array_unref(body);
			g_byte_array_unref(frames);
			g_byte_array_unref(header);
		}
		g_free(encoded);
	}
	g_object_unref(image);
	decode("gif", gif, sizeof(gif), 1, 1, 0x336699, 0);
	decode("legacy-xpm", (const guint8 *)xpm, strlen(xpm), 2, 2, 0x336699, 0);
	decode("xbm", (const guint8 *)xbm, strlen(xbm), 8, 8, 0, 0);
	bytes = g_byte_array_new();
	g_byte_array_append(bytes, (const guint8 *)"P6\n16 16\n255\n", 13);
	for (i = 0; i < 256; i++)
		g_byte_array_append(bytes, rgb, 3);
	decode("pnm", bytes->data, bytes->len, 16, 16, 0x336699, 0);
	g_byte_array_set_size(bytes, 0);
	g_byte_array_append(bytes, tga, sizeof(tga));
	for (i = 0; i < 256; i++)
		g_byte_array_append(bytes, bgr, 3);
	decode("tga", bytes->data, bytes->len, 16, 16, 0x336699, 0);
	g_byte_array_set_size(bytes, 0);
	g_byte_array_append(bytes, (const guint8 *)"icns", 4);
	append32(bytes, 8 + 8 + sizeof(icns) + 8 + sizeof(mask), TRUE);
	for (c = 0; c < 3; c++) {
		icns[c * 4] = icns[c * 4 + 2] = 253;
		icns[c * 4 + 1] = icns[c * 4 + 3] = rgb[c];
	}
	memset(mask, 255, sizeof(mask));
	g_byte_array_append(bytes, (const guint8 *)"is32", 4);
	append32(bytes, sizeof(icns) + 8, TRUE);
	g_byte_array_append(bytes, icns, sizeof(icns));
	g_byte_array_append(bytes, (const guint8 *)"s8mk", 4);
	append32(bytes, sizeof(mask) + 8, TRUE);
	g_byte_array_append(bytes, mask, sizeof(mask));
	decode("icns", bytes->data, bytes->len, 16, 16, 0x336699, 0);
	g_byte_array_unref(bytes);
}

static void
metadata(void)
{
	GIRepository *repository = gi_repository_new();
	GError *error = NULL;
	GBytes *bytes;
	GITypelib *typelib;
	GIBaseInfo *info;
	GIFunctionInfo *constructor;
	GIArgument args[5] = { { 0 }, { 0 }, { 0 }, { 0 }, { 0 } }, result;
	unsigned int i;

	for (i = 0; i < G_N_ELEMENTS(typelibs); i++) {
		bytes = g_bytes_new_static(typelibs[i].start,
		    typelibs[i].end - typelibs[i].start);
		typelib = gi_typelib_new_from_bytes(bytes, &error);
		g_assert_no_error(error);
		g_assert_nonnull(gi_repository_load_typelib(repository,
		    typelib, GI_REPOSITORY_LOAD_FLAG_LAZY, &error));
		g_assert_no_error(error);
		gi_typelib_unref(typelib);
		g_bytes_unref(bytes);
	}
	info = gi_repository_find_by_name(repository, "GdkPixbuf", "Pixbuf");
	g_assert_true(GI_IS_OBJECT_INFO(info));
	constructor = gi_object_info_find_method(GI_OBJECT_INFO(info), "new");
	g_assert_nonnull(constructor);
	args[0].v_int = GDK_COLORSPACE_RGB;
	args[1].v_boolean = FALSE;
	args[2].v_int = 8;
	args[3].v_int = args[4].v_int = 16;
	g_assert_true(gi_function_info_invoke(constructor, args, 5, NULL, 0,
	    &result, &error));
	g_assert_no_error(error);
	g_assert_true(GDK_IS_PIXBUF(result.v_pointer));
	g_assert_cmpint(gdk_pixbuf_get_width(result.v_pointer), ==, 16);
	g_object_unref(result.v_pointer);
	g_assert_false(gi_function_info_invoke(constructor, args, 4, NULL, 0,
	    &result, &error));
	g_assert_error(error, GI_INVOKE_ERROR, GI_INVOKE_ERROR_ARGUMENT_MISMATCH);
	g_clear_error(&error);
	gi_base_info_unref((GIBaseInfo *)constructor);
	gi_base_info_unref(info);
	g_object_unref(repository);
}

int
main(void)
{
	GError *error = NULL;
	GdkPixbufLoader *loader;
	gchar *root, *path, *text, **parts, *argv[3];
	int status;
	unsigned int i, cycle;
	gboolean accepted;

	g_assert_cmpint(g_mkdir_with_parents("fixture/mime/packages", 0700), ==, 0);
	root = g_canonicalize_filename("fixture", NULL);
	for (i = 0; i < G_N_ELEMENTS(assets); i++) {
		path = g_build_filename(root, assets[i].path, NULL);
		g_assert_true(g_file_set_contents(path, (const char *)assets[i].start,
		    assets[i].end - assets[i].start, &error));
		g_assert_no_error(error);
		g_free(path);
	}
	parts = g_strsplit(cache_template, "@MODULE_DIR@", -1);
	text = g_strjoinv(root, parts);
	path = g_build_filename(root, "loaders.cache", NULL);
	g_assert_true(g_file_set_contents(path, text, -1, &error));
	g_assert_no_error(error);
	g_setenv("GDK_PIXBUF_MODULE_FILE", path, TRUE);
	g_setenv("XDG_DATA_DIRS", root, TRUE);
	g_setenv("XDG_DATA_HOME", root, TRUE);
	g_free(path);
	g_free(text);
	g_strfreev(parts);
	argv[0] = g_build_filename(root, "update-mime-database", NULL);
	argv[1] = g_build_filename(root, "mime", NULL);
	argv[2] = NULL;
	g_assert_cmpint(g_chmod(argv[0], 0700), ==, 0);
	g_assert_true(g_spawn_sync(NULL, argv, NULL, 0, NULL, NULL, NULL,
	    NULL, &status, &error));
	g_assert_no_error(error);
	g_assert_true(g_spawn_check_wait_status(status, &error));
	g_assert_no_error(error);
	g_free(argv[0]);
	g_free(argv[1]);
	for (cycle = 0; cycle < 4; cycle++) {
		formats();
		metadata();
		loader = gdk_pixbuf_loader_new_with_type("png", &error);
		g_assert_no_error(error);
		accepted = gdk_pixbuf_loader_write(loader,
		    (const guint8 *)"invalid image", 13, &error);
		if (accepted)
			accepted = gdk_pixbuf_loader_close(loader, &error);
		else
			gdk_pixbuf_loader_close(loader, NULL);
		g_assert_false(accepted);
		g_assert_nonnull(error);
		g_clear_error(&error);
		g_object_unref(loader);
		printf("cycle %u: invalid PNG/signature refused; target GI invocation PASS\n", cycle + 1);
	}
	g_free(root);
	puts("PASS: all 13 loader formats, four decode/metadata lifecycles, current MIME database");
	return 0;
}
