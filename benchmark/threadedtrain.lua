local Threads = require 'threads'

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

   Threads.serialization('threads.sharedserialize')
   local threads = Threads(
      params.threads,
      function()
         require 'nn'
      end,

      function()
         local module = module:clone('weight', 'bias')
         local weights, dweights = module:parameters()
         local criterion = criterion:clone()
         local data = data
         local label = label
         local dataset = {}

         local nex = label:size(1)

         if params.batch == 1 then
            function dataset:size()
               return nex
            end

            setmetatable(dataset, {__index =
                                       function(self, index)
                                          return {data[index], label[index]}
                                       end})
         else
            assert(nex % params.batch == 0, '# of examples must be divisible with batch size')
            local batch = params.batch
            function dataset:size()
               return nex/batch
            end
            setmetatable(dataset, {__index =
                                       function(self, index)
                                         return {
                                            data:narrow(1,(index-1)*batch+1, batch),
                                            label:narrow(1,(index-1)*batch+1, batch)
                                         }
                                       end})
         end

         function gupdate(idx)
            local ex = dataset[idx]
            local x, y = ex[1], ex[2]
            local z = module:forward(x)
            local err = criterion:forward(z, y)
            module:zeroGradParameters()
            module:updateGradInput(x, criterion:updateGradInput(module.output, y))
            module:accGradParameters(x, criterion.gradInput)
            return err, dweights
         end

      end
   )

   local weights = module:parameters()
   for iter=1,params.iter do
      local totalerr = 0
      local idx = 1
      while idx < label:size(1)/params.batch do

         threads:addjob(
            function(idx)
               return gupdate(idx)
            end,

            function(err, dweights)
               totalerr = totalerr + err
               for i=1,#weights do
                  weights[i]:add(-0.01, dweights[i])
               end
            end,
            idx
         )

         idx = idx + 1
      end
      threads:synchronize()
      print('# current error = ', totalerr/label:size(1))
   end

   threads:terminate()

end

return threadedTrain
