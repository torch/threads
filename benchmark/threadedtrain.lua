local ffi = require 'ffi'
local Threads = require 'threads'

require 'utils'

local function threadedTrain(module, criterion, data, label, params)

   -- corner case: we are here to do batches
   -- no bach, no threading
   if params.batch == 1 then
      print('! WARNING: no batch => no thread')
      params.threads = 1
   end

   if params.threads == 1 then
      print('! WARNING: if you use no thread, better not use a thread-aware code [overheads ahead]')
   end

   -- important because of possible sub-batch per thread
   -- in the end, we normalize ourselves per batch-size
   criterion.sizeAverage = false

   local weight = module:getParameters()
   local weight_p = tonumber(ffi.cast('intptr_t', weight:data()))
   local weight_nelem = weight:nElement()
   local data_p = tonumber(ffi.cast('intptr_t', data:data()))
   local label_p = tonumber(ffi.cast('intptr_t', label:data()))

   local data_size = data:size()
   local data_nelem = data:nElement()
   local label_size = label:size()
   local label_nelem = label:nElement()

   local threads, gradweights = Threads(params.threads,
                           function()
                              require 'nn'
                              require 'utils'
                           end,
                           
                           function()
                              local ffi = require 'ffi'

                              gmodule = module
                              gcriterion = criterion

                              sharefloatstorage(gmodule:get(1).weight:storage(), weight_p)
                              gdatastorage = torch.FloatStorage()
                              sharefloatstorage(gdatastorage, data_p, data_nelem)
                              gdata = torch.FloatTensor(gdatastorage, 1, data_size)

                              glabelstorage = torch.LongStorage()
                              sharelongstorage(glabelstorage, label_p, label_nelem)
                              glabel = torch.LongTensor(glabelstorage, 1, label_size)

                              gdataset = {}

                              local nex = glabel:size(1)

                              if params.batch == 1 or params.batch == params.threads then
                                 function gdataset:size()
                                    return nex
                                 end

                                 setmetatable(gdataset, {__index = function(self, index)
                                                                      return {gdata[index], glabel[index]}
                                                                   end})
                              else
                                 assert(nex % params.batch == 0, '# of examples must be divisible with batch size')
                                 assert(params.batch % params.threads == 0, 'batch size must be divisible threads')
                                 local n = params.batch/params.threads
                                 function gdataset:size()
                                    return nex/n
                                 end
                                 setmetatable(gdataset, {__index = function(self, index)
                                                                      return {gdata:narrow(1,(index-1)*n+1, n),
                                                                         glabel:narrow(1,(index-1)*n+1, n)}
                                                                   end})
                              end

                              function gupdate(idx)
                                 local ex = gdataset[idx]
                                 local x, y = ex[1], ex[2]
                                 
                                 local z = gmodule:forward(x)
                                 local err = gcriterion:forward(z, y)
                                 gmodule:zeroGradParameters()
                                 gmodule:updateGradInput(x, gcriterion:updateGradInput(gmodule.output, y))
                                 gmodule:accGradParameters(x, gcriterion.gradInput)

                                 return err
                              end

                              return tonumber(ffi.cast('intptr_t', gmodule:get(1).gradWeight:data()))
                           end)


   for i=1,params.threads do
      local gradweight = torch.FloatStorage()
      sharefloatstorage(gradweight, gradweights[i][1], weight_nelem)
      gradweights[i] = torch.FloatTensor(gradweight)
   end

   for iter=1,params.iter do
      local totalerr = 0
      for b=1,label:size(1)/params.batch do
         for t=1,params.threads do
            local idx = (b-1)*params.threads + t
                              
            threads:addjob(function(idx)
                              return gupdate(idx)
                           end,

                           function(err)
                              totalerr = totalerr + err
                           end,

                           idx
                        )
         end
         threads:synchronize()
         for i=1,params.threads do
            weight:add(-0.01/params.batch, gradweights[i])
         end
      end
      print('# current error = ', totalerr/label:size(1))
   end

   threads:terminate()

end

return threadedTrain
