#include <lua.h>
#include <lauxlib.h>

#ifndef HAS_LUAL_SETFUNCS
static void luaL_setfuncs(lua_State *L, const luaL_Reg *l, int nup)
{
  luaL_checkstack(L, nup+1, "too many upvalues");
  for (; l->name != NULL; l++) {  /* fill the table with given functions */
    int i;
    lua_pushstring(L, l->name);
    for (i = 0; i < nup; i++)  /* copy upvalues to the top */
      lua_pushvalue(L, -(nup+1));
    lua_pushcclosure(L, l->func, nup);  /* closure with those upvalues */
    lua_settable(L, -(nup + 3));
  }
  lua_pop(L, nup);  /* remove upvalues */
}
#endif

#if LUA_VERSION_NUM >= 503
#define luaL_checklong(L,n)     ((long)luaL_checkinteger(L, (n)))
#define luaL_checkint(L,n)      ((int)luaL_checkinteger(L, (n)))
#endif

#define luaL_checkaddr(L,n)     ((AddressType)luaL_checkinteger(L, (n)))

#include "threads.c"
#include "queue.c"

#if defined(_WIN32)
__declspec(dllexport) int _cdecl luaopen_libthreads(lua_State *L)
#else
int luaopen_libthreads(lua_State *L)
#endif
{
  lua_newtable(L);
  thread_init_pkg(L);
  queue_init_pkg(L);
  return 1;
}
