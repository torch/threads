local clib = require 'libthreads'

local unpack = unpack or table.unpack
local Queue = clib.Queue

function Queue:addjob(callback, ...)
   local args = {...}
   local status, msg = pcall(
      function()
         self.mutex:lock()
         while self.isfull == 1 do
            self.notfull:wait(self.mutex)
         end

         local serialize = require(self.serialize)

         self:callback(self.tail, serialize.save(callback))
         self:arg(self.tail, serialize.save(args))

         self.tail = self.tail + 1
         if self.tail == self.size then
            self.tail = 0
         end
         if self.tail == self.head then
            self.isfull = 1
         end
         self.isempty = 0

         self.mutex:unlock()
         self.notempty:signal()
      end
   )
   if not status then
      print(string.format('FATAL THREAD PANIC: (addjob) %s', msg))
      os.exit(-1)
   end
end

function Queue:dojob()
   local status, msg = pcall(
      function()
         local serialize = require(self.serialize)

         self.mutex:lock()
         while self.isempty == 1 do
            self.notempty:wait(self.mutex)
         end


         local callback = serialize.load(self:callback(self.head))
         local args = serialize.load(self:arg(self.head))

         self.head = self.head + 1
         if self.head == self.size then
            self.head = 0
         end
         if self.head == self.tail then
            self.isempty = 1
         end
         self.isfull = 0

         self.mutex:unlock()
         self.notfull:signal()

         local res = {callback(unpack(args))} -- note: args is a table for sure
         return res
      end
   )
   if not status then
      print(string.format('FATAL THREAD PANIC: (dojob) %s', msg))
      os.exit(-1)
   end
   return unpack(msg)
end

return Queue
