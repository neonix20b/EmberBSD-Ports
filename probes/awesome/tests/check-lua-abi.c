/* SPDX-License-Identifier: BSD-2-Clause */
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>

#if LUA_VERSION_NUM != 504
#error "The probe must use the operating system's Lua 5.4 headers"
#endif

int
main(void)
{
	lua_State *L = luaL_newstate();
	if (L == NULL)
		return 1;
	luaL_checkversion(L);
	luaL_openlibs(L);
	if (luaL_dostring(L, "assert(_VERSION == 'Lua 5.4')") != LUA_OK) {
		fprintf(stderr, "%s\n", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}
	puts(LUA_RELEASE);
	lua_close(L);
	return 0;
}
