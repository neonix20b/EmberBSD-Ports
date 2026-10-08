/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD (AI-assisted), installed text shaping and PNG consumer. */
#define _NETBSD_SOURCE
#include <sys/types.h>
#include <link.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <glib.h>
#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <hb-ft.h>
#include <pango/pangocairo.h>
#include <pango/pangofc-fontmap.h>
#include <pango/pangofc-font.h>

#define WIDTH 640
#define HEIGHT 192
#define REQUIRE(test, reason) do { \
	if (!(test)) { failure = (reason); goto done; } \
} while (0)

static int
loaded(struct dl_phdr_info *info, size_t size, void *argument)
{
	(void)size;
	if (info->dlpi_name != NULL && info->dlpi_name[0] != '\0' &&
	    strcmp(info->dlpi_name, (const char *)argument) != 0)
		printf("LOADED: %s\n", info->dlpi_name);
	return 0;
}

static bool
cycle(const char *font_file, const char *png_file, unsigned number,
    const char *executable)
{
	const char *failure = NULL;
	FcConfig *config = NULL;
	FcPattern *pattern = NULL, *matched = NULL;
	FcChar8 *resolved = NULL;
	FcResult match_result;
	FT_Library ft = NULL;
	FT_Face face = NULL;
	hb_font_t *hb_font = NULL;
	hb_buffer_t *shaped = NULL;
	hb_feature_t liga;
	GError *error = NULL;
	GRegex *regex = NULL;
	GMatchInfo *match = NULL;
	char *capture = NULL;
	PangoFontMap *map = NULL;
	PangoContext *context = NULL;
	PangoLayout *layout = NULL;
	PangoFontDescription *description = NULL;
	PangoLayoutIter *iter = NULL;
	PangoRectangle ink, logical;
	cairo_surface_t *surface = NULL, *decoded = NULL;
	cairo_t *cr = NULL;
	cairo_font_options_t *options = NULL;
	unsigned painted = 0, glyphs = 0, runs = 0;
	bool success = false;
	/* Latin ligatures, Cyrillic codepoints and Arabic joining in one layout. */
	const char *text = "office AV\n"
	    "\320\237\321\200\320\270\320\262\320\265\321\202\n"
	    "\330\263\331\204\330\247\331\205";

	regex = g_regex_new("^(\\p{L}+)-([0-9]+)$", 0, 0, &error);
	REQUIRE(regex != NULL && error == NULL, "GLib/PCRE2 compile");
	REQUIRE(g_regex_match(regex, "Ember-42", 0, &match), "GLib/PCRE2 match");
	capture = g_match_info_fetch(match, 2);
	REQUIRE(capture != NULL && strcmp(capture, "42") == 0, "PCRE2 capture value");
	REQUIRE(g_utf8_validate(text, -1, NULL), "UTF-8 test input");

	config = FcConfigCreate();
	REQUIRE(config != NULL && FcConfigAppFontAddFile(config,
	    (const FcChar8 *)font_file) && FcConfigBuildFonts(config), "private font configuration");
	FcFontSet *fonts = FcConfigGetFonts(config, FcSetApplication);
	REQUIRE(fonts != NULL && fonts->nfont == 1, "exactly one fixture font");
	pattern = FcNameParse((const FcChar8 *)"DejaVu Sans");
	REQUIRE(pattern != NULL && FcConfigSubstitute(config, pattern,
	    FcMatchPattern), "fontconfig substitution");
	FcDefaultSubstitute(pattern);
	matched = FcFontMatch(config, pattern, &match_result);
	REQUIRE(matched != NULL && FcPatternGetString(matched, FC_FILE, 0,
	    &resolved) == FcResultMatch && strcmp((const char *)resolved,
	    font_file) == 0, "fontconfig selected the exact fixture");

	REQUIRE(FT_Init_FreeType(&ft) == 0 && FT_New_Face(ft, font_file, 0,
	    &face) == 0 && FT_Set_Pixel_Sizes(face, 0, 32) == 0, "FreeType load and size");
	hb_font = hb_ft_font_create_referenced(face);
	REQUIRE(hb_font != NULL, "HarfBuzz FreeType font");
	for (unsigned enabled = 0; enabled != 2; enabled++) {
		shaped = hb_buffer_create();
		REQUIRE(shaped != NULL && hb_buffer_allocation_successful(shaped), "HarfBuzz buffer");
		hb_buffer_add_utf8(shaped, "ffi", -1, 0, -1);
		hb_buffer_guess_segment_properties(shaped);
		REQUIRE(hb_feature_from_string(enabled ? "liga=1" : "liga=0", -1,
		    &liga), "HarfBuzz feature parse");
		hb_shape(hb_font, shaped, &liga, 1);
		unsigned count = 0;
		hb_glyph_info_t *info = hb_buffer_get_glyph_infos(shaped, &count);
		REQUIRE(count == (enabled ? 1U : 3U), "real ffi ligature on/off shaping");
		for (unsigned i = 0; i < count; i++)
			REQUIRE(info[i].codepoint != 0, "nonmissing shaped glyph");
		hb_buffer_destroy(shaped);
		shaped = NULL;
	}

	map = pango_cairo_font_map_new_for_font_type(CAIRO_FONT_TYPE_FT);
	REQUIRE(map != NULL && PANGO_IS_FC_FONT_MAP(map), "Pango FreeType backend");
	pango_fc_font_map_set_config(PANGO_FC_FONT_MAP(map), config);
	context = pango_font_map_create_context(map);
	REQUIRE(context != NULL, "Pango context");
	options = cairo_font_options_create();
	cairo_font_options_set_antialias(options, CAIRO_ANTIALIAS_GRAY);
	cairo_font_options_set_hint_style(options, CAIRO_HINT_STYLE_NONE);
	pango_cairo_context_set_font_options(context, options);
	pango_cairo_context_set_resolution(context, 96);
	layout = pango_layout_new(context);
	description = pango_font_description_from_string("DejaVu Sans 24");
	REQUIRE(layout != NULL && description != NULL, "Pango layout");
	pango_layout_set_font_description(layout, description);
	pango_layout_set_text(layout, text, -1);
	pango_layout_set_width(layout, (WIDTH - 32) * PANGO_SCALE);
	REQUIRE(pango_layout_get_line_count(layout) == 3 &&
	    pango_layout_get_unknown_glyphs_count(layout) == 0, "three lines without missing glyphs");
	pango_layout_get_pixel_extents(layout, &ink, &logical);
	printf("EXTENTS: ink=%d,%d,%d,%d logical=%d,%d,%d,%d\n",
	    ink.x, ink.y, ink.width, ink.height, logical.x, logical.y,
	    logical.width, logical.height);
	/* A right-to-left line can fill the configured logical layout width. */
	REQUIRE(ink.width > 30 && ink.height > 30 && logical.x >= 0 &&
	    logical.y >= 0 && logical.x + logical.width <= WIDTH - 32 &&
	    logical.y + logical.height <= HEIGHT - 32,
	    "bounded nonempty text extents");
	iter = pango_layout_get_iter(layout);
	REQUIRE(iter != NULL, "Pango run iterator");
	do {
		PangoLayoutRun *run = pango_layout_iter_get_run_readonly(iter);
		if (run == NULL)
			continue;
		REQUIRE(PANGO_IS_FC_FONT(run->item->analysis.font), "fontconfig-backed run");
		FcPattern *selected = pango_fc_font_get_pattern(PANGO_FC_FONT(run->item->analysis.font));
		REQUIRE(FcPatternGetString(selected, FC_FILE, 0, &resolved) == FcResultMatch &&
		    strcmp((const char *)resolved, font_file) == 0, "every run uses the sealed fixture");
		glyphs += run->glyphs->num_glyphs;
		runs++;
	} while (pango_layout_iter_next_run(iter));
	REQUIRE(runs >= 3 && glyphs >= 10, "actual shaped Pango runs");
	surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, WIDTH, HEIGHT);
	REQUIRE(cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS, "Cairo image allocation");
	cr = cairo_create(surface);
	cairo_set_source_rgb(cr, 1, 1, 1);
	cairo_paint(cr);
	cairo_set_source_rgb(cr, 0, 0, 0);
	cairo_move_to(cr, 16, 16);
	pango_cairo_show_layout(cr, layout);
	REQUIRE(cairo_status(cr) == CAIRO_STATUS_SUCCESS, "Pango/Cairo drawing");
	cairo_surface_flush(surface);
	unsigned char *data = cairo_image_surface_get_data(surface);
	int stride = cairo_image_surface_get_stride(surface);
	for (int y = 0; y < HEIGHT; y++) {
		const uint32_t *row = (const uint32_t *)(data + y * stride);
		for (int x = 0; x < WIDTH; x++) {
			if (row[x] == UINT32_C(0xffffffff))
				continue;
			REQUIRE((row[x] >> 24) == 255 && x >= 15 + ink.x &&
			    x <= 17 + ink.x + ink.width && y >= 15 + ink.y &&
			    y <= 17 + ink.y + ink.height, "painted pixels stay in declared ink bounds");
			painted++;
		}
	}
	REQUIRE(painted > 100 && painted < WIDTH * HEIGHT / 2, "text changes the white image");
	REQUIRE(cairo_surface_write_to_png(surface, png_file) == CAIRO_STATUS_SUCCESS,
	    "PNG encode through installed libpng");
	decoded = cairo_image_surface_create_from_png(png_file);
	REQUIRE(cairo_surface_status(decoded) == CAIRO_STATUS_SUCCESS &&
	    cairo_image_surface_get_width(decoded) == WIDTH &&
	    cairo_image_surface_get_height(decoded) == HEIGHT, "PNG dimensions after decode");
	cairo_surface_flush(decoded);
	cairo_format_t format = cairo_image_surface_get_format(decoded);
	REQUIRE(format == CAIRO_FORMAT_ARGB32 || format == CAIRO_FORMAT_RGB24,
	    "supported decoded pixel format");
	for (int y = 0; y < HEIGHT; y++) {
		const uint32_t *before = (const uint32_t *)(data + y * stride);
		const uint32_t *after = (const uint32_t *)(cairo_image_surface_get_data(decoded) +
		    y * cairo_image_surface_get_stride(decoded));
		for (int x = 0; x < WIDTH; x++) {
			/* Cairo leaves RGB24's high byte unused; its pixels are opaque. */
			uint32_t pixel = format == CAIRO_FORMAT_RGB24 ?
			    after[x] | UINT32_C(0xff000000) : after[x];
			REQUIRE(before[x] == pixel, "exact PNG pixel roundtrip");
		}
	}
	REQUIRE(dl_iterate_phdr(loaded, (void *)executable) == 0, "live library inventory");
	success = true;
done:
	if (failure != NULL)
		fprintf(stderr, "FAIL cycle %u: %s\n", number, failure);
	if (decoded != NULL)
		cairo_surface_destroy(decoded);
	if (cr != NULL)
		cairo_destroy(cr);
	if (surface != NULL)
		cairo_surface_destroy(surface);
	if (iter != NULL)
		pango_layout_iter_free(iter);
	if (layout != NULL)
		g_object_unref(layout);
	if (description != NULL)
		pango_font_description_free(description);
	if (options != NULL)
		cairo_font_options_destroy(options);
	if (context != NULL)
		g_object_unref(context);
	if (map != NULL) {
		pango_fc_font_map_shutdown(PANGO_FC_FONT_MAP(map));
		g_object_unref(map);
	}
	if (shaped != NULL)
		hb_buffer_destroy(shaped);
	if (hb_font != NULL)
		hb_font_destroy(hb_font);
	if (face != NULL)
		FT_Done_Face(face);
	if (ft != NULL)
		FT_Done_FreeType(ft);
	if (matched != NULL)
		FcPatternDestroy(matched);
	if (pattern != NULL)
		FcPatternDestroy(pattern);
	if (config != NULL)
		FcConfigDestroy(config);
	g_free(capture);
	if (match != NULL)
		g_match_info_free(match);
	if (regex != NULL)
		g_regex_unref(regex);
	if (error != NULL)
		g_error_free(error);
	if (success)
		printf("PASS cycle %u: PCRE2 capture, exact font, ffi shaping, %u runs, %u glyphs, %u ink pixels, PNG roundtrip and cleanup\n",
		    number, runs, glyphs, painted);
	return success;
}

int
main(int argc, char **argv)
{
	setvbuf(stdout, NULL, _IOLBF, 0);
	if (argc != 3 || argv[1][0] != '/' || argv[2][0] != '/') {
		fprintf(stderr, "Usage: text-render ABSOLUTE_FONT ABSOLUTE_PNG_OUTPUT\n");
		return 2;
	}
	printf("VERSIONS: GLib %u.%u.%u; Pango %s; HarfBuzz %s; Cairo %s; Fontconfig %d\n",
	    glib_major_version, glib_minor_version, glib_micro_version,
	    pango_version_string(), hb_version_string(), cairo_version_string(), FcGetVersion());
	for (unsigned i = 1; i <= 4; i++)
		if (!cycle(argv[1], argv[2], i, argv[0]))
			return 1;
	char *png = NULL;
	gsize size = 0;
	if (!g_file_get_contents(argv[2], &png, &size, NULL) || size > 1024 * 1024) {
		fputs("FAIL: read back bounded PNG artifact\n", stderr);
		g_free(png);
		return 1;
	}
	char *encoded = g_base64_encode((const guchar *)png, size);
	printf("PNG64: %s\n", encoded);
	g_free(encoded);
	g_free(png);
	puts("PASS: four installed text shaping/rasterization/PNG lifecycles");
	return 0;
}
