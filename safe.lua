-- utility for lua 5.2
local setfenv = setfenv or
   function(fn, env)
      local i = 1
      while true do
         local name = debug.getupvalue(fn, i)
         if name == "_ENV" then
            debug.upvaluejoin(fn, i, (function()
                                         return env
                                      end), 1)
            break
         elseif not name then
            break
         end
         i = i + 1
      end
      return fn
   end

local function newproxygc(func)
   local proxy
   if newproxy then -- 5.1
      proxy = newproxy(true)
      getmetatable(proxy).__gc = func
   else -- 5.2
      proxy = {}
      setmetatable(proxy, {__gc=func})
   end
   return proxy
end

return function(func, mutex)
   local threads = require 'threads'

   assert(type(func) == 'function', 'function, [mutex] expected')
   assert(mutex == nil or getmetatable(threads.Mutex).__index == getmetatable(mutex).__index, 'function, [mutex] expected')

   -- make sure mutex is freed if it is our own
   local proxy
   if not mutex then
      mutex = threads.Mutex()
      proxy = newproxygc(
         function()
            mutex:free()
         end
      )
   end

   local mutexid = mutex:id()
   local safe =
      function(...)
         local threads = require 'threads'
         local mutex = threads.Mutex(mutexid)
         local unpack = unpack or table.unpack
         mutex:lock()
         local res = {func(...)}
         mutex:unlock()
         return unpack(res)
      end

   -- make sure mutex is freed if it is our own
   if proxy then
      setfenv(safe, {require=require, unpack=unpack, table=table, proxy=proxy})
   end

   return safe
end
