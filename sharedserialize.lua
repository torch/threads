local ffi = require 'ffi'
local C = ffi.C

ffi.cdef[[
void free(void *ptr);
void *malloc(size_t size);
]]

require 'torch'

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
         local code = torch.serialize(func) -- DEBUG: make it work without torch too ;)
         local sz = #code
         local code_p = ffi.cast('char*', C.malloc(sz)) -- C.malloc(sz+1))
         assert(code_p ~= nil, 'allocation error during serialization')
         ffi.copy(code_p, ffi.cast('const char*', code), sz)
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
         local code = ffi.string(code_p, sz)
         C.free(ffi.cast('void*', code_p))
         return torch.deserialize(code)
      end
   )
   unshareread()
   if not status then
      error(func)
   end
   return func
end

return serialize
