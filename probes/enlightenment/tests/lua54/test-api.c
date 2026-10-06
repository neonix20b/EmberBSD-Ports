/* Regression on EFL's extracted Edje argument conversion functions. */
#include <assert.h>
#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#ifdef HAVE_EFL_LUA_COMPAT
#include "efl_lua_compat.h"
#endif
#define EINA_FALSE 0
#define EINA_TRUE 1
typedef unsigned char Eina_Bool;
#include "edje-scanner.c"

int
main(int argc, char **argv)
{
   lua_State *L = luaL_newstate();
   int x = 0, y = 0, w = 0, h = 0;
   assert(L && argc == 2);
   luaL_openlibs(L);
   assert(luaL_dostring(L, "return 12.75, -5.5, 8.5, 9.25") == 0);
   assert(_elua_scan_params(L, 1, "%x %y %w %h", &x, &y, &w, &h) == 4);
   if (x != 12 || y != -5 || w != 8 || h != 9)
     {
        fprintf(stderr, "FAIL: fractional geometry became %d,%d %dx%d\n", x, y, w, h);
        return 1;
     }
   lua_settop(L, 0);
   assert(luaL_dostring(L, "return {x=12.75, y=-5.5, w=8.5, h=9.25}") == 0);
   assert(_elua_scan_params(L, 1, "%x %y %w %h", &x, &y, &w, &h) == 1);
   assert(x == 12 && y == -5 && w == 8 && h == 9);
   assert(lua_gettop(L) == 1);
   lua_settop(L, 0);
   assert(luaL_dostring(L, "return {r=127.75, g=63.5, b=31.25, a=255}") == 0);
   assert(_elua_scan_params(L, 1, "%r %g %b %a", &x, &y, &w, &h) == 1);
   assert(x == 127 && y == 63 && w == 31 && h == 255);
   lua_settop(L, 0);
   if (luaL_loadfile(L, argv[1]) || lua_pcall(L, 0, 1, 0))
     {
        fprintf(stderr, "color.lua: %s\n", lua_tostring(L, -1));
        return 1;
     }
   lua_setglobal(L, "color");
   if (luaL_dostring(L,
       "local c = color(64,128,192,255) * color(128,96,64,127) "
       "assert(c.r > 32 and c.r < 33) "
       "assert(tostring(c) == '#2030307f', tostring(c)) "
       "local b = color(64,128,192,128):blend(color(128,64,32,127)) "
       "assert(tostring(b) == string.format('#%02x%02x%02x%02x', "
       "math.floor(b.r), math.floor(b.g), math.floor(b.b), math.floor(b.a)))"))
     {
        fprintf(stderr, "FAIL: color arithmetic: %s\n", lua_tostring(L, -1));
        return 1;
     }
   printf("PASS: Lua %s, extracted Edje fractional geometry/colors and Evas color arithmetic\n", LUA_VERSION);
   lua_close(L);
   return 0;
}
