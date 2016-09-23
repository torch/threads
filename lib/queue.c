#include "TH.h" /* for THCharStorage */
#include "luaT.h" /* for handling THCHarStorage */
#include "luaTHRD.h"
#include "THThread.h"
#include <lua.h>
#include <lualib.h>
#include <lualib.h>


typedef struct THQueue_ {
  THMutex *mutex;
  THCondition *notfull;
  THCondition *notempty;
  THCharStorage **callbacks;
  THCharStorage **args;
  char* serialize;

  int head;
  int tail;
  int isempty;
  int isfull;
  int size;
  int refcount;
} THQueue;

static int queue_new(lua_State *L)
{
  THQueue *queue = NULL;

  if(lua_gettop(L) == 1) {

    queue = (THQueue*)luaL_checkinteger(L, 1);
    THMutex_lock(queue->mutex);
    queue->refcount = queue->refcount + 1;
    THMutex_unlock(queue->mutex);

  } else if(lua_gettop(L) == 2) {

    int size = luaL_checkint(L, 1);
    const char *serialize = luaL_checkstring(L, 2);
    size_t serialize_len;
    lua_tolstring(L, 2, &serialize_len);

    queue = calloc(1, sizeof(THQueue)); /* zeroed */
    if(!queue)
      goto outofmem;

    queue->mutex = THMutex_new();
    queue->notfull = THCondition_new();
    queue->notempty = THCondition_new();
    queue->callbacks = calloc(size, sizeof(THCharStorage*));
    queue->args = calloc(size, sizeof(THCharStorage*));
    queue->serialize = malloc(serialize_len+1);
    if(queue->serialize)
      memcpy(queue->serialize, serialize, serialize_len+1);

    queue->head = 0;
    queue->tail = 0;
    queue->isempty = 1;
    queue->isfull = 0;
    queue->size = size;
    queue->refcount = 1;

    if(!queue->mutex || !queue->notfull || !queue->notempty
       || !queue->callbacks || !queue->args || !queue->serialize)
      goto outofmemfree;

  } else
    luaL_error(L, "threads: queue new invalid arguments");

  if(!luaTHRD_pushudata(L, queue, "threads.Queue"))
    goto outofmemfree;

  return 1;


  outofmemfree:
  THMutex_free(queue->mutex);
  THCondition_free(queue->notfull);
  THCondition_free(queue->notempty);
  free(queue->callbacks);
  free(queue->args);
  free(queue->serialize);
  free(queue);
  outofmem:
  luaL_error(L, "threads: queue new out of memory");
  return 0;
}

static int queue_free(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  if(THAtomicDecrementRef(&queue->refcount))
  {
    int i;
    THMutex_free(queue->mutex);
    THCondition_free(queue->notfull);
    THCondition_free(queue->notempty);
    for(i = 0; i < queue->size; i++) {
      if(queue->callbacks[i])
        THCharStorage_free(queue->callbacks[i]);
      if(queue->args[i])
        THCharStorage_free(queue->args[i]);
    }
    free(queue->serialize);
    free(queue->callbacks);
    free(queue->args);
    free(queue);
  }
  return 0;
}

static int queue_retain(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  THAtomicIncrementRef(&queue->refcount);
  return 0;
}

static int queue_get_mutex(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  return luaTHRD_pushudata(L, queue->mutex, "threads.Mutex");
}

static int queue_get_notfull(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  return luaTHRD_pushudata(L, queue->notfull, "threads.Condition");
}

static int queue_get_notempty(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  return luaTHRD_pushudata(L, queue->notempty, "threads.Condition");
}

static int queue_get_serialize(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  lua_pushstring(L, queue->serialize);
  return 1;
}

static int queue_get_head(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  lua_pushnumber(L, queue->head);
  return 1;
}

static int queue_get_tail(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  lua_pushnumber(L, queue->tail);
  return 1;
}

static int queue_get_isempty(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  lua_pushnumber(L, queue->isempty);
  return 1;
}

static int queue_get_isfull(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  lua_pushnumber(L, queue->isfull);
  return 1;
}

static int queue_get_size(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  lua_pushnumber(L, queue->size);
  return 1;
}

static int queue__index(lua_State *L)
{
  luaTHRD_checkudata(L, 1, "threads.Queue");
  lua_getmetatable(L, 1);
  if(lua_isstring(L, 2)) {
    lua_pushstring(L, "__get");
    lua_rawget(L, -2);
    lua_pushvalue(L, 2);
    lua_rawget(L, -2);
    if(lua_isfunction(L, -1)) {
      lua_pushvalue(L, 1);
      lua_call(L, 1, 1);
      return 1;
    }
    else {
      lua_pop(L, 2);
    }
  }
  lua_insert(L, -2);
  lua_rawget(L, -2);
  return 1;
}

static int queue_callback(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  int idx = luaL_checkint(L, 2);
  luaL_argcheck(L, idx >= 0 && idx < queue->size, 2, "out of range");
  if(lua_gettop(L) == 2) {
    THCharStorage *storage = NULL;
    if((storage = queue->callbacks[idx])) {
      THCharStorage_retain(storage);
      luaT_pushudata(L, storage, "torch.CharStorage");
      return 1;
    }
    else
      return 0;
  }
  else if(lua_gettop(L) == 3) {
    THCharStorage *storage = luaT_checkudata(L, 3, "torch.CharStorage"); /* DEBUG: might be luaT for torch objects */
    if(queue->callbacks[idx]) {
      THCharStorage_free(queue->callbacks[idx]);
    }
    queue->callbacks[idx] = storage;
    THCharStorage_retain(storage);
    return 0;
  }
  else
    luaL_error(L, "invalid arguments");
  return 0;
}

static int queue_arg(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  int idx = luaL_checkint(L, 2);
  luaL_argcheck(L, idx >= 0 && idx < queue->size, 2, "out of range");
  if(lua_gettop(L) == 2) {
    THCharStorage *storage = NULL;
    if((storage = queue->args[idx])) {
      THCharStorage_retain(storage);
      luaT_pushudata(L, storage, "torch.CharStorage");
      return 1;
    }
    else
      return 0;
  }
  else if(lua_gettop(L) == 3) {
    THCharStorage *storage = luaT_checkudata(L, 3, "torch.CharStorage"); /* DEBUG: might be luaT for torch objects */
    if(queue->args[idx])
      THCharStorage_free(queue->args[idx]);
    queue->args[idx] = storage;
    THCharStorage_retain(storage);
    return 0;
  }
  else
    luaL_error(L, "invalid arguments");
  return 0;
}


/* */

static int queue_set_head(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  int value = luaL_checkint(L, 2);
  queue->head = value;
  return 0;
}

static int queue_set_tail(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  int value = luaL_checkint(L, 2);
  queue->tail = value;
  return 0;
}

static int queue_set_isempty(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  int value = luaL_checkint(L, 2);
  queue->isempty = value;
  return 0;
}

static int queue_set_isfull(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  int value = luaL_checkint(L, 2);
  queue->isfull = value;
  return 0;
}

static int queue__newindex(lua_State *L)
{
  luaTHRD_checkudata(L, 1, "threads.Queue");
  if(lua_gettop(L) != 3)
    luaL_error(L, "invalid arguments");

  lua_getmetatable(L, 1);
  if(lua_isstring(L, 2)) {
    lua_pushstring(L, "__set");
    lua_rawget(L, -2);
    lua_pushvalue(L, 2);
    lua_rawget(L, -2);
    if(lua_isfunction(L, -1)) {
      lua_pushvalue(L, 1);
      lua_pushvalue(L, 3);
      lua_call(L, 2, 0);
      return 0;
    }
    else
      luaL_error(L, "invalid argument");
  }
  luaL_error(L, "invalid argument");
  return 0;
}

static int queue_id(lua_State *L)
{
  THQueue *queue = luaTHRD_checkudata(L, 1, "threads.Queue");
  lua_pushinteger(L, (AddressType)queue);
  return 1;
}

static const struct luaL_Reg queue__ [] = {
  {"new", queue_new},
  {"id", queue_id},
  {"retain", queue_retain},
  {"free", queue_free},
  {"callback", queue_callback},
  {"arg", queue_arg},
  {"__gc", queue_free},
  {"__index", queue__index},
  {"__newindex", queue__newindex},
  {NULL, NULL}
};

static const struct luaL_Reg queue_get__ [] = {
  {"mutex", queue_get_mutex},
  {"notfull", queue_get_notfull},
  {"notempty", queue_get_notempty},
  {"serialize", queue_get_serialize},
  {"head", queue_get_head},
  {"tail", queue_get_tail},
  {"isempty", queue_get_isempty},
  {"isfull", queue_get_isfull},
  {"size", queue_get_size},
  {NULL, NULL}
};

static const struct luaL_Reg queue_set__ [] = {
  {"head", queue_set_head},
  {"tail", queue_set_tail},
  {"isempty", queue_set_isempty},
  {"isfull", queue_set_isfull},
  {NULL, NULL}
};

static void queue_init_pkg(lua_State *L)
{
  if(!luaL_newmetatable(L, "threads.Queue"))
    luaL_error(L, "threads: threads.Queue type already exists");
  luaL_setfuncs(L, queue__, 0);

  lua_pushstring(L, "__get");
  lua_newtable(L);
  luaL_setfuncs(L, queue_get__, 0);
  lua_rawset(L, -3);

  lua_pushstring(L, "__set");
  lua_newtable(L);
  luaL_setfuncs(L, queue_set__, 0);
  lua_rawset(L, -3);

  lua_pop(L, 1);

  lua_pushstring(L, "Queue");
  luaTHRD_pushctortable(L, queue_new, "threads.Queue");
  lua_rawset(L, -3);
}
