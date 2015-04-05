local ffi = require 'ffi'
local C = ffi.C

require 'torch'

local status, tds = pcall(require, 'tds')

ffi.cdef[[
void free(void *ptr);
void *malloc(size_t size);
THCharStorage* THCharStorage_newWithData(const char *data, long size);
void THCharStorage_clearFlag(THCharStorage *storage, const char flag);

void THByteTensor_retain(THByteTensor *self);
void THCharTensor_retain(THCharTensor *self);
void THShortTensor_retain(THShortTensor *self);
void THIntTensor_retain(THIntTensor *self);
void THLongTensor_retain(THLongTensor *self);
void THFloatTensor_retain(THFloatTensor *self);
void THDoubleTensor_retain(THDoubleTensor *self);

void THByteStorage_retain(THByteStorage *self);
void THCharStorage_retain(THCharStorage *self);
void THShortStorage_retain(THShortStorage *self);
void THIntStorage_retain(THIntStorage *self);
void THLongStorage_retain(THLongStorage *self);
void THFloatStorage_retain(THFloatStorage *self);
void THDoubleStorage_retain(THDoubleStorage *self);
]]

if torch.CudaTensor then
   ffi.cdef[[
void THCudaTensor_retain(THCudaTensor *self);
void THCudaStorage_retain(THCudaStorage *self);
]]
end

local serialize = {}

local typenames = {}

-- check if typenames exists
for _, typename in ipairs{
   'torch.ByteTensor',
   'torch.CharTensor',
   'torch.ShortTensor',
   'torch.IntTensor',
   'torch.LongTensor',
   'torch.CudaTensor',
   'torch.FloatTensor',
   'torch.DoubleTensor',
   'torch.CudaTensor',
   'torch.ByteStorage',
   'torch.CharStorage',
   'torch.ShortStorage',
   'torch.IntStorage',
   'torch.LongStorage',
   'torch.CudaStorage',
   'torch.FloatStorage',
   'torch.DoubleStorage',
   'torch.CudaStorage',
   'tds_hash'} do

   if torch.getmetatable(typename) then
      typenames[typename] = {}
   end

end

if typenames.tds_hash then
   local mt = typenames.tds_hash

   function mt.__factory(f)
      local self = f:readLong()
      self = ffi.cast('tds_hash&', self)
      ffi.gc(self, tds.C.tds_hash_free)
      return self
   end

   function mt.__write(self, f)
      f:writeLong(torch.pointer(self))
      tds.C.tds_hash_retain(self)
   end

   function mt.__read(self, f)
   end
end

for _, typename in ipairs{
   'torch.ByteTensor',
   'torch.CharTensor',
   'torch.ShortTensor',
   'torch.IntTensor',
   'torch.LongTensor',
   'torch.CudaTensor',
   'torch.FloatTensor',
   'torch.DoubleTensor',
   'torch.CudaTensor',
   'torch.ByteStorage',
   'torch.CharStorage',
   'torch.ShortStorage',
   'torch.IntStorage',
   'torch.LongStorage',
   'torch.CudaStorage',
   'torch.FloatStorage',
   'torch.DoubleStorage',
   'torch.CudaStorage'} do

   if typenames[typename] then
      local mt = typenames[typename]
      local thname = typename:gsub('torch%.', 'TH')
      local retain = C[thname .. '_retain']

      function mt.__factory(f)
         local self = f:readLong()
         self = torch.pushudata(self, typename)
         return self
      end

      function mt.write(self, f)
         f:writeLong(torch.pointer(self))
         retain(self:cdata())
      end

      function mt.read(self, f)
      end
   end
end

local function swapwrite()
   for typename, mt in pairs(typenames) do
      local mts = torch.getmetatable(typename)
      mts.__write, mt.__write = mt.__write, mts.__write
      mts.write, mt.write = mt.write, mts.write
   end
end

local function swapread()
   for typename, mt in pairs(typenames) do
      local mts = torch.getmetatable(typename)
      mts.__factory, mt.__factory = mt.__factory, mts.__factory
      mts.__read, mt.__read = mt.__read, mts.__read
      mts.read, mt.read = mt.read, mts.read
   end
end

function serialize.save(func)
   local status, msg = pcall(swapwrite)
   if not status then
      print(string.format('FATAL THREAD PANIC: (write) %s', msg))
      os.exit(-1)
   end

   local status, code_p, sz = pcall(
      function()
         local f = torch.MemoryFile()
         f:binary()
         f:writeObject(func)
         local storage = f:storage()
         local code_p = storage:data()
         local sz = storage:size()
         -- refcounted, but do not free mem
         C.THCharStorage_clearFlag(storage:cdata(), 4)
         f:close()
         return code_p, sz
      end
   )
   if not status then
      print(string.format('FATAL THREAD PANIC: (write) %s', code_p))
      os.exit(-1)
   end

   local status, msg = pcall(swapwrite)
   if not status then
      print(string.format('FATAL THREAD PANIC: (write) %s', msg))
      os.exit(-1)
   end

   return code_p, sz
end

function serialize.load(code_p, sz)
   local status, msg = pcall(swapread)
   if not status then
      print(string.format('FATAL THREAD PANIC: (read) %s', msg))
      os.exit(-1)
   end

   local status, func = pcall(
      function()
         local storage_p = C.THCharStorage_newWithData(code_p, sz)
         local storage = torch.pushudata(storage_p, 'torch.CharStorage')
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
