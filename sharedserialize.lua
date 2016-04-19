require 'torch'
local ffi = require 'ffi'

local serialize = {}
local typenames = {}

local function serializePointer(obj, f)
   -- on 32-bit systems double can represent all possible
   -- pointer values, but signed long can't
   if ffi.sizeof('long') == 4 then
      f:writeDouble(torch.pointer(obj))
   -- on 64-bit systems, long can represent a larger
   -- range of integers than double, so it's safer to use this
   else
      f:writeLong(torch.pointer(obj))
   end
end

local function deserializePointer(f)
   if ffi.sizeof('long') == 4 then
      return f:readDouble()
   else
      return f:readLong()
   end
end

-- tds support
local _, tds = pcall(require, 'tds') -- for the free/retain functions
if tds then

   -- hash
   local mt = {}
   function mt.__factory(f)
      local self = deserializePointer(f)
      self = ffi.cast('tds_hash&', self)
      ffi.gc(self, tds.C.tds_hash_free)
      return self
   end
   function mt.__write(self, f)
      serializePointer(self, f)
      tds.C.tds_hash_retain(self)
   end
   function mt.__read(self, f)
   end
   typenames['tds.Hash'] = mt

   -- vec
   local mt = {}
   function mt.__factory(f)
      local self = deserializePointer(f)
      self = ffi.cast('tds_vec&', self)
      ffi.gc(self, tds.C.tds_vec_free)
      return self
   end
   function mt.__write(self, f)
      serializePointer(self, f)
      tds.C.tds_vec_retain(self)
   end
   function mt.__read(self, f)
   end
   typenames['tds.Vec'] = mt
end

-- tensor support
for _, typename in ipairs{
   'torch.ByteTensor',
   'torch.CharTensor',
   'torch.ShortTensor',
   'torch.IntTensor',
   'torch.LongTensor',
   'torch.FloatTensor',
   'torch.DoubleTensor',
   'torch.CudaTensor',
   'torch.ByteStorage',
   'torch.CharStorage',
   'torch.ShortStorage',
   'torch.IntStorage',
   'torch.LongStorage',
   'torch.FloatStorage',
   'torch.DoubleStorage',
   'torch.CudaStorage',
   'torch.Allocator'} do

   local mt = {}

   function mt.__factory(f)
      local self = deserializePointer(f)
      self = torch.pushudata(self, typename)
      return self
   end

   function mt.write(self, f)
      serializePointer(self, f)
      if typename ~= 'torch.Allocator' then
         self:retain()
      end
   end

   function mt.read(self, f)
   end

   typenames[typename] = mt
end

local function swapwrite()
   for typename, mt in pairs(typenames) do
      local mts = torch.getmetatable(typename)
      if mts then
         mts.__factory, mt.__factory = mt.__factory, mts.__factory
         mts.__write, mt.__write = mt.__write, mts.__write
         mts.write, mt.write = mt.write, mts.write
      end
   end
end

local function swapread()
   for typename, mt in pairs(typenames) do
      local mts = torch.getmetatable(typename)
      if mts then
         mts.__factory, mt.__factory = mt.__factory, mts.__factory
         mts.__read, mt.__read = mt.__read, mts.__read
         mts.read, mt.read = mt.read, mts.read
      end
   end
end

function serialize.save(func)
   local status, msg = pcall(swapwrite)
   if not status then
      print(string.format('FATAL THREAD PANIC: (write) %s', msg))
      os.exit(-1)
   end

   local status, storage = pcall(
      function()
         local f = torch.MemoryFile()
         f:binary()
         f:writeObject(func)
         local storage = f:storage()
         f:close()
         return storage
      end
   )
   if not status then
      print(string.format('FATAL THREAD PANIC: (write) %s', storage))
      os.exit(-1)
   end

   local status, msg = pcall(swapwrite)
   if not status then
      print(string.format('FATAL THREAD PANIC: (write) %s', msg))
      os.exit(-1)
   end

   return storage
end

function serialize.load(storage)
   local status, msg = pcall(swapread)
   if not status then
      print(string.format('FATAL THREAD PANIC: (read) %s', msg))
      os.exit(-1)
   end

   local status, func = pcall(
      function()
         local f = torch.MemoryFile(storage)
         f:binary()
         local func = f:readObject()
         f:close()
         return func
      end
   )
   if not status then
      print(string.format('FATAL THREAD PANIC: (read) %s', func))
      os.exit(-1)
   end

   local status, msg = pcall(swapread)
   if not status then
      print(string.format('FATAL THREAD PANIC: (read) %s', msg))
      os.exit(-1)
   end

   return func
end

return serialize
