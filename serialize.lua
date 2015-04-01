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

function serialize.save(func)
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

function serialize.load(code_p, sz)
   local storage_p = C.THCharStorage_newWithData(code_p, sz)
   local storage = torch.pushudata(storage_p, 'torch.CharStorage')
   local f = torch.MemoryFile(storage)
   f:binary()
   local func = f:readObject()
   f:close()
   return func
end

return serialize
