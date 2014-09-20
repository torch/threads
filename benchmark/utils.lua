local ffi = require 'ffi'

local TH_STORAGE_REFCOUNTED = 1
local TH_STORAGE_RESIZABLE  = 2
local TH_STORAGE_FREEMEM    = 4

function sharefloatstorage(storage, data_p, sz)
   local storage_p = ffi.cast('THFloatStorage*', torch.pointer(storage))
   assert(bit.band(storage_p.flag, TH_STORAGE_REFCOUNTED) ~= 0)

   if storage_p.data ~= nil then
      storage_p.allocator.free(storage_p.allocatorContext, storage_p.data)
   end

   storage_p.data = ffi.cast('float*', data_p)
   if sz then
      storage_p.size = sz
   end

   storage_p.flag = TH_STORAGE_REFCOUNTED
end

function sharelongstorage(storage, data_p, sz)
   local storage_p = ffi.cast('THLongStorage*', torch.pointer(storage))
   assert(bit.band(storage_p.flag, TH_STORAGE_REFCOUNTED) ~= 0)

   if storage_p.data ~= nil then
      storage_p.allocator.free(storage_p.allocatorContext, storage_p.data)
   end

   storage_p.data = ffi.cast('long*', data_p)
   if sz then
      storage_p.size = sz
   end

   storage_p.flag = TH_STORAGE_REFCOUNTED
end
