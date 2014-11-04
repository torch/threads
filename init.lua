local ffi = require 'ffi'
local sdl = require 'sdl2'
local Worker = require 'threads.worker'
local C = ffi.C
local serialize = require 'threads.serialize'

ffi.cdef[[
typedef struct lua_State lua_State;
      lua_State *luaL_newstate(void);
      void luaL_openlibs(lua_State *L);
      void lua_close(lua_State *L);
      int luaL_loadstring(lua_State *L, const char *s);
      int lua_pcall(lua_State *L, int nargs, int nresults, int errfunc);

      ptrdiff_t lua_tointeger(lua_State *L, int index);
      void lua_settop(lua_State *L, int index);

      void lua_getfield(lua_State *L, int index, const char *k);
      const char *lua_tolstring (lua_State *L, int index, size_t *len);
]]

local LUA_GLOBALSINDEX = -10002;

local Threads = {__index=Threads, name="worker"}

setmetatable(Threads, Threads)

local function checkL(L, status)
   if not status then
      local msg = ffi.string(C.lua_tolstring(L, -1, NULL))
      error(msg)
   end
end

function Threads:__call(N, ...)
   local self = {N=N, endcallbacks={n=0}, errors={}}
   local funcs = {...}
   local initres = {}

   setmetatable(self, {__index=Threads})

   self.mainworker = Worker(N)
   self.threadworker = Worker(N)

   self.threads = {}
   for i=1,N do
      local L = C.luaL_newstate()
      assert(L ~= nil, string.format('%d-th lua state creation failed', i))
      C.luaL_openlibs(L)

      for j=1,#funcs do
         local code_p, sz = serialize.save(funcs[j])
         if j < #funcs then
            checkL(L, C.luaL_loadstring(L, string.format([[
              local serialize = require 'threads.serialize'
              local ffi = require 'ffi'
              local code = serialize.load(ffi.cast('const char*', %d), %d)
              code(%d)
            ]], tonumber(ffi.cast('intptr_t', code_p)), sz, i)))
         else
            checkL(L, C.luaL_loadstring(L, string.format([[
              local serialize = require 'threads.serialize'
              local ffi = require 'ffi'
              local code = serialize.load(ffi.cast('const char*', %d), %d)
              __threadid = %d
              __workerinitres_p, __workerinitres_sz = serialize.save{code(%d)}
              __workerinitres_p = tonumber(ffi.cast('intptr_t', __workerinitres_p))
            ]], tonumber(ffi.cast('intptr_t', code_p)), sz, i, i)))
         end
         checkL(L, C.lua_pcall(L, 0, 0, 0) == 0)
      end

      C.lua_getfield(L, LUA_GLOBALSINDEX, '__workerinitres_p')
      local workerinitres_p = C.lua_tointeger(L, -1)
      C.lua_getfield(L, LUA_GLOBALSINDEX, '__workerinitres_sz')
      local workerinitres_sz = C.lua_tointeger(L, -1)
      C.lua_settop(L, -3)
      table.insert(initres, serialize.load(ffi.cast('const char*', workerinitres_p), workerinitres_sz))

      checkL(L, C.luaL_loadstring(L, [[
  local ffi = require 'ffi'
  local sdl = require 'sdl2'
  require 'threads.worker'

  local function workerloop(data)
     local workers = ffi.cast('struct THWorker**', data)
     local mainworker = workers[0]
     local threadworker = workers[1]
     local threadid = __threadid

     while __worker_running do
        local status, res, endcallbackid = threadworker:dojob()
        mainworker:addjob(function()
                             return status, res, endcallbackid, threadid
                          end)
     end

     return 0
  end

  __worker_running = true
  __workerloop_ptr = tonumber(ffi.cast('intptr_t', ffi.cast('int (*)(void *)', workerloop)))
]]
) == 0)
      checkL(L, C.lua_pcall(L, 0, 0, 0) == 0)
      C.lua_getfield(L, LUA_GLOBALSINDEX, '__workerloop_ptr')
      local workerloop_ptr = C.lua_tointeger(L, -1)
      C.lua_settop(L, -2);

      local workers = ffi.new('struct THWorker*[2]', {self.mainworker, self.threadworker}) -- note: GCed
      local thread = sdl.createThread(ffi.cast('SDL_ThreadFunction', workerloop_ptr), string.format("%s%.2d", Threads.name, i), workers)
      assert(thread ~= nil, string.format('%d-th thread creation failed', i))
      table.insert(self.threads, {thread=thread, L=L})
   end

   return self, initres
end

function Threads:dojob()
   local endcallbacks = self.endcallbacks
   local callstatus, args, endcallbackid, threadid = self.mainworker:dojob()
   if callstatus then
      local endcallstatus, msg = pcall(endcallbacks[endcallbackid], unpack(args))
      if not endcallstatus then
         table.insert(self.errors, string.format('[thread %d endcallback] %s', threadid, msg))
      end
   else
      table.insert(self.errors, string.format('[thread %d callback] %s', threadid, args[1]))
   end
   endcallbacks[endcallbackid] = nil
   endcallbacks.n = endcallbacks.n - 1
end

function Threads:addjob(callback, endcallback, ...) -- endcallback is passed with returned values of callback
   if #self.errors > 0 then self:synchronize() end -- if errors exist, sync immediately.
   local endcallbacks = self.endcallbacks

   -- first finish running jobs if any
   while self.mainworker.isempty ~= 1 do
      self:dojob()
   end

   -- now add a new endcallback in the list
   local endcallbackid = table.getn(endcallbacks)+1
   endcallbacks[endcallbackid] = endcallback or function() end
   endcallbacks.n = endcallbacks.n + 1

   local func = function(...)
      local res = {pcall(callback, ...)}
      local status = table.remove(res, 1)
      return status, res, endcallbackid
   end

   self.threadworker:addjob(func, ...)
end

function Threads:synchronize()

   while self.mainworker.runningjobs > 0 or self.threadworker.runningjobs > 0 or self.endcallbacks.n > 0 do
      self:dojob()
   end

   if #self.errors > 0 then
      local msg = string.format('\n%s', table.concat(self.errors, '\n'))
      self.errors = {}
      error(msg)
   end
end

function Threads:terminate()
   -- terminate the threads
   for i=1,self.N do
      self:addjob(function()
                     __worker_running = false
                  end)
   end

   -- terminate all jobs
   self:synchronize()

   -- wait for threads to exit (and free them)
   local pvalue = ffi.new('int[1]')
   for i=1,self.N do
      sdl.waitThread(self.threads[i].thread, pvalue)
      C.lua_close(self.threads[i].L)
   end
end

return Threads --createThreads
