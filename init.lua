local ffi = require 'ffi'
local sdl = require 'sdl2'
local Worker = require 'threads.worker'
local C = ffi.C

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

local Threads = {name="worker"}

setmetatable(Threads, Threads)

local function checkL(L, status)
   if not status then
      local msg = ffi.string(C.lua_tolstring(L, -1, NULL))
      error(msg)
   end
end

Threads.__serialize = "threads.serialize"

function Threads.serialization(name)
   if name then
      assert(type(name) == 'string')
      Threads.__serialize = name
   else
      return Threads.__serialize
   end
end

function Threads:__call(N, ...)
   local self = {N=N, endcallbacks={n=0}, errors={}, __specific=true}
   local funcs = {...}
   local serialize = require(Threads.__serialize)

   if #funcs == 0 then
      funcs = {function() end}
   end


   setmetatable(self, {__index=Threads})

   self.mainworker = Worker(N, Threads.__serialize)
   self.threadworker = Worker(N, Threads.__serialize)
   self.threadspecificworkers = {}

   self.threads = {}
   for i=1,N do
      self.threadspecificworkers[i] = Worker(N, Threads.__serialize)

      local L = C.luaL_newstate()
      assert(L ~= nil, string.format('%d-th lua state creation failed', i))
      C.luaL_openlibs(L)

      checkL(L,
             C.luaL_loadstring(
                L,
                string.format(
                   [[
  local ffi = require 'ffi'
  local sdl = require 'sdl2'
  require 'threads.worker'

  __threadid = %d
  local function workerloop(data)
     local workers = ffi.cast('struct THWorker**', data)
     local mainworker = workers[0]
     local threadworker = workers[1]
     local threadspecificworker = workers[2]
     local threadid = __threadid

     while __worker_running do
        local status, res, endcallbackid
        if __worker_specific then
          status, res, endcallbackid = threadspecificworker:dojob()
        else
          status, res, endcallbackid = threadworker:dojob()
        end
        mainworker:addjob(function()
                             return status, res, endcallbackid, threadid
                          end)
     end

     return 0
  end

  __worker_running = true
  __worker_specific = true
  __workerloop_ptr = tonumber(ffi.cast('intptr_t', ffi.cast('int (*)(void *)', workerloop)))
]],
                   i)
             ) == 0)

      checkL(L, C.lua_pcall(L, 0, 0, 0) == 0)
      C.lua_getfield(L, LUA_GLOBALSINDEX, '__workerloop_ptr')
      local workerloop_ptr = C.lua_tointeger(L, -1)
      C.lua_settop(L, -2);

      local workers = ffi.new('struct THWorker*[3]', {self.mainworker, self.threadworker, self.threadspecificworkers[i]}) -- note: GCed
      local thread = sdl.createThread(ffi.cast('SDL_ThreadFunction', workerloop_ptr), string.format("%s%.2d", Threads.name, i), workers)
      assert(thread ~= nil, string.format('%d-th thread creation failed', i))
      table.insert(self.threads, {thread=thread, L=L})
   end

   self.__gc__ = newproxy(true)
   getmetatable(self.__gc__).__gc =
     function()
         self:synchronize()
     end

   local initres = {}
   for j=1,#funcs do
      for i=1,self.N do
         if j ~= #funcs then
            self:addjob(
               i, -- specific
               funcs[j],
               function()
               end,
               i -- passed to callback
            )
         else
            self:addjob(
               i, -- specific
               funcs[j],
               function(...)
                  table.insert(initres, {...})
               end,
               i -- passed to callback
            )
         end
      end
   end
   self:synchronize()
   self:specific(false)

   return self, initres
end

function Threads:specific(flag)
   if flag ~= nil then
      assert(type(flag) == 'boolean', 'boolean expected')
      self:synchronize() -- finish jobs first
      if self.__specific ~= flag then
         if self.__specific then
            for i=1,self.N do
               self:addjob(i,
                           function()
                              __worker_specific = false
                           end)
            end
         else
            for i=1,self.N do
               self:addjob(function()
                              __worker_specific = true
                           end)
            end
         end
         self.__specific = flag
      end
   else
      return self.__specific
   end
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

function Threads:acceptsjob(idx)
   local threadworker
   if self:specific() then
      assert(type(idx) == 'number' and idx >= 1 and idx <= self.N, 'thread index expected')
      threadworker = self.threadspecificworkers[idx]
   else
      threadworker = self.threadworker
   end
   return threadworker.isfull ~= 1
end

function Threads:__addjob__(sync, ...) -- endcallback is passed with returned values of callback
   if #self.errors > 0 then self:synchronize() end -- if errors exist, sync immediately.
   local endcallbacks = self.endcallbacks

   local idx, threadworker, r, callback, endcallback
   if self:specific() then
      idx = select(1, ...)
      assert(type(idx) == 'number' and idx >= 1 and idx <= self.N, 'thread index expected')
      threadworker = self.threadspecificworkers[idx]
      callback = select(2, ...)
      endcallback = select(3, ...)
      r = 4
   else
      callback = select(1, ...)
      endcallback = select(2, ...)
      threadworker = self.threadworker
      r = 3
   end
   assert(type(callback) == 'function', 'function callback expected')
   assert(type(endcallback) == 'function' or type(endcallback) == 'nil', 'function (or nil) endcallback expected')

   -- first finish running jobs if any
   if sync then
      while not self:acceptsjob(idx) do
         self:dojob()
      end
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

   threadworker:addjob(func, select(r, ...))
end

function Threads:addjob(...)
   self:__addjob__(true, ...)
end

function Threads:addjobasync(...)
   self:__addjob__(false, ...)
end

function Threads:haserror()
   return (#self.errors > 0)
end

function Threads:hasjob()
   return self.endcallbacks.n > 0
end

function Threads:synchronize()
   while self:hasjob()do
      self:dojob()
   end
   if self:haserror() then
      local msg = string.format('\n%s', table.concat(self.errors, '\n'))
      self.errors = {}
      error(msg)
   end
end

function Threads:terminate()
   -- terminate the threads
   for i=1,self.N do
      if self:specific() then
         self:addjob(
            i,
            function()
               __worker_running = false
            end)
      else
         self:addjob(
            function()
               __worker_running = false
            end)
      end
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
