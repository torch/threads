#ifndef LUA_THRD_INC
#define LUA_THRD_INC

#if (LUA_VERSION_NUM >= 502)
#define lua_equal(L, idx1, idx2)  lua_compare(L, (idx1), (idx2), LUA_OPEQ)
#endif

static int luaTHRD_pushudata(lua_State *L, void *ptr, const char* typename)
{
  void **udata = lua_newuserdata(L, sizeof(void*));
  if(udata) {
    *udata = ptr;
    luaL_getmetatable(L, typename);
    lua_setmetatable(L, -2);
    return 1;
  }
  return 0;
}

static void *luaTHRD_checkudata(lua_State *L, int narg, const char *typename)
{
  void **udata = luaL_checkudata(L, narg, typename);
  if(udata)
    return *udata;
  else
    return NULL;
}

static void *luaTHRD_toudata(lua_State *L, int narg, const char *typename)
{
  void **udata = lua_touserdata(L, narg);
  if(udata) {
    if(lua_getmetatable(L, -1)) {
      luaL_getmetatable(L, typename);
      if(lua_equal(L, -1, -2)) {
        lua_pop(L, 2);
        return *udata;
      }
      else {
        lua_pop(L, 2);
        return NULL;
      }
    }
    else
      return NULL;
  }
  else
    return NULL;
}

static int luaTHRD_ctor(lua_State *L)
{
  if(!lua_istable(L, 1)) /* dummy ctor table */
    luaL_error(L, "ctor: table expected");
  lua_getmetatable(L, 1);
  lua_remove(L, 1); /* dummy ctor table */
  if(!lua_istable(L, -1))
    luaL_error(L, "ctor: no metatable found");
  lua_pushstring(L, "__new");
  lua_rawget(L, -2);
  lua_remove(L, -2); /* forget about metatable */
  if(!lua_isfunction(L, -1))
    luaL_error(L, "ctor: __new appears to be not a function");
  lua_insert(L, 1); /* ctor first, arguments follow */
  lua_call(L, lua_gettop(L)-1, LUA_MULTRET);
  return lua_gettop(L);
}

static void luaTHRD_pushctortable(lua_State *L, lua_CFunction ctor, const char* typename)
{
  lua_newtable(L); /* empty useless dude */
  lua_newtable(L); /* metatable of the dude */
  lua_pushstring(L, "__index");
  luaL_getmetatable(L, typename);
  lua_rawset(L, -3);
  lua_pushstring(L, "__newindex");
  luaL_getmetatable(L, typename);
  lua_rawset(L, -3);
  lua_pushstring(L, "__new"); /* __call will look into there */
  lua_pushcfunction(L, ctor);
  lua_rawset(L, -3);
  lua_pushstring(L, "__call"); /* pop the table and calls __new */
  lua_pushcfunction(L, luaTHRD_ctor);
  lua_rawset(L, -3);
  lua_setmetatable(L, -2);
}

#endif
