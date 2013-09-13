local ffi = require 'ffi'
local C = ffi.C

ffi.cdef[[
void free(void *ptr);
void *malloc(size_t size);
]]

require 'torch'

local serialize = {}

function serialize.save(func)
   local code = torch.serialize(func) -- DEBUG: make it work without torch too ;)
   local sz = #code
   local code_p = ffi.cast('char*', C.malloc(sz)) -- C.malloc(sz+1))
   assert(code_p ~= nil, 'allocation error during serialization')
--   code_p[sz] = 0
   ffi.copy(code_p, ffi.cast('const char*', code), sz)
   return code_p, sz
end

function serialize.load(code_p, sz)
   local code = ffi.string(code_p, sz)
   C.free(ffi.cast('void*', code_p))
   return torch.deserialize(code)
end

return serialize
