/* Compile and render a Lua-backed Edje theme and real Evas filters. */
#define EFL_GFX_FILTER_BETA
#define EFL_BETA_API_SUPPORT
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <Ecore.h>
#include <Ecore_Evas.h>
#include <Edje.h>
#include <Evas.h>

static int version_seen;
static int geometry_seen;

static void
message(void *data, Evas_Object *obj, Edje_Message_Type type, int id, void *msg)
{
   (void)data;
   (void)obj;
   if (id == 501 && type == EDJE_MESSAGE_STRING)
     {
        Edje_Message_String *m = msg;
        version_seen = strcmp(m->str, "Lua 5.4") == 0;
     }
   if (id == 502 && type == EDJE_MESSAGE_INT_SET)
     {
        Edje_Message_Int_Set *m = msg;
        const int expected[] = {5, 9, 17, 13, 200, 40, 20, 255};
        geometry_seen = m->count == 8;
        for (int i = 0; geometry_seen && i < 8; i++)
          geometry_seen = m->val[i] == expected[i];
     }
}

static void
check_pixel(Ecore_Evas *ee, int x, int y, uint32_t expected)
{
   ecore_evas_manual_render(ee);
   const uint32_t *pixels = ecore_evas_buffer_pixels_get(ee);
   assert(pixels);
   uint32_t actual = pixels[y * 64 + x];
   if (actual != expected)
     {
        fprintf(stderr, "FAIL: pixel (%d,%d) is %#x, expected %#x\n", x, y, actual, expected);
        assert(actual == expected);
     }
}

int
main(int argc, char **argv)
{
   assert(argc == 2);
   ecore_app_no_system_modules();
   assert(ecore_evas_init() > 0);
   assert(edje_init() > 0);
   Ecore_Evas *ee = ecore_evas_buffer_new(64, 64);
   assert(ee);
   ecore_evas_alpha_set(ee, EINA_TRUE);
   ecore_evas_transparent_set(ee, EINA_TRUE);
   ecore_evas_manual_render_set(ee, EINA_TRUE);
   ecore_evas_show(ee);
   Evas *canvas = ecore_evas_get(ee);
   Evas_Object *layout = edje_object_add(canvas);
   assert(layout);
   edje_object_message_handler_set(layout, message, NULL);
   assert(edje_object_file_set(layout, argv[1], "lua54"));
   evas_object_resize(layout, 64, 64);
   evas_object_show(layout);
   edje_message_signal_process();
   assert(version_seen && geometry_seen);
   check_pixel(ee, 6, 10, UINT32_C(0xffc82814));
   check_pixel(ee, 0, 0, 0);
   evas_object_del(layout);
   puts("PASS: compiled Edje Lua 5.4 theme, fractional geometry/colors, messages and pixels");

   Evas_Object *image = evas_object_image_filled_add(canvas);
   assert(image);
   uint32_t white = UINT32_C(0xffffffff);
   evas_object_image_size_set(image, 1, 1);
   evas_object_image_data_copy_set(image, &white);
   evas_object_move(image, 16, 16);
   evas_object_resize(image, 16, 16);
   evas_object_show(image);
   const char *filter =
     "local tmp = buffer('rgba') "
     "local c = color(64,128,192,255) * color(128,96,64,255) "
     "assert(tostring(c) == '#203030ff') "
     "padding_set { 1.5, 2.5, 3.5, 4.5 } "
     "blend { src = input, dst = tmp, color = c } "
     "blend { src = tmp, dst = output }";
   efl_gfx_filter_program_set(image, filter, "lua54-filter");
   int l = 0, r = 0, t = 0, b = 0;
   efl_gfx_filter_padding_get(image, &l, &r, &t, &b);
   assert(l == 1 && r == 2 && t == 3 && b == 4);
   check_pixel(ee, 20, 20, UINT32_C(0xff203030));
   puts("PASS: real Evas buffer/filter registration, fractional padding, color arithmetic and output pixels");
   evas_object_del(image);
   ecore_evas_free(ee);
   edje_shutdown();
   ecore_evas_shutdown();
   return 0;
}
