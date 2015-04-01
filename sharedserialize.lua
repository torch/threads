local ffi = require 'ffi'
local C = ffi.C

require 'torch'

ffi.cdef[[
void free(void *ptr);
void *malloc(size_t size);
THCharStorage* THCharStorage_newWithData(const char *data, long size);
void THCharStorage_clearFlag(THCharStorage *storage, const char flag);
]]

local serialize = {}

local tensor = {}
local tensortypes = {}

for _, name in ipairs{
   'ByteTensor',
   'CharTensor',
   'ShortTensor',
   'IntTensor',
   'LongTensor',
   'CudaTensor',
   'FloatTensor',
   'DoubleTensor',
   'CudaTensor'} do

   if torch[name] then
      table.insert(tensortypes, name)
      tensor[name] = {
         read  = torch[name].read,
         write = torch[name].write
      }
   end

end

local function tensor_write(self, f)
   f:writeLong(torch.pointer(self))
   local p = self:cdata()
   p.refcount = p.refcount + 1
end

local function tensor_read(self, f)
   local p = f:readLong()
   local z = torch.pushudata(p, torch.typename(self))
   self:set(z)
end

local function sharewrite()
   for _, name in ipairs(tensortypes) do
      torch[name].write = tensor_write
   end
end

local function unsharewrite()
   for _, name in ipairs(tensortypes) do
      torch[name].write = tensor[name].write
   end
end

local function shareread()
   for _, name in ipairs(tensortypes) do
      torch[name].read = tensor_read
   end
end

local function unshareread()
   for _, name in ipairs(tensortypes) do
      torch[name].read = tensor[name].read
   end
end

function serialize.save(func)
   sharewrite()
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
   unsharewrite()
   if not status then
      error(code_p)
   end
   return code_p, sz
end

function serialize.load(code_p, sz)
   shareread()
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
   unshareread()
   if not status then
      error(func)
   end
   return func
end

return serialize
