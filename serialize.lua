require 'torch'

local serialize = {}

function serialize.save(func)
   local f = torch.MemoryFile()
   f:binary()
   f:writeObject(func)
   local storage = f:storage()
   f:close()
   return storage
end

function serialize.load(storage)
   local f = torch.MemoryFile(storage)
   f:binary()
   local func = f:readObject()
   f:close()
   return func
end

return serialize
