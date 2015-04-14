#include "threads.c"
#include "queue.c"

int luaopen_libthreads(lua_State *L)
{
  lua_newtable(L);
  thread_init_pkg(L);
  queue_init_pkg(L);
  return 1;
}
