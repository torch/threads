#include <stdio.h>
#include <stdlib.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include "THThread.h"

static int runthread(void *code_)
{
  char *code = code_;
  lua_State *L = luaL_newstate();

  if(!L) {
    printf("THREAD FATAL ERROR: could not create lua state\n");
    return -1;
  }
  luaL_openlibs(L);

  if(luaL_loadstring(L, code)) {
    printf("FATAL THREAD PANIC: (loadstring) %s\n", lua_tolstring(L, -1, NULL));
    free(code);
    lua_close(L);
    return -1;
  }

  free(code);
  if(lua_pcall(L, 0, 0, 0)) {
    printf("FATAL THREAD PANIC: (pcall) %s\n", lua_tolstring(L, -1, NULL));
    lua_close(L);
    return -1;
  }

  lua_close(L);
  return 0;
}

#if defined(_WIN32)
__declspec(dllexport) void* _cdecl THThread_main(void *arg)
#else
void* THThread_main(void *arg)
#endif
{
  THThreadState* state = arg;
  state->status = runthread(state->data);
  return NULL;
}
