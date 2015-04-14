require 'torch'

local threads = require 'threads'
local status, tds = pcall(require, 'tds')
tds = status and tds or nil

local nthread = 4
local njob = 10
local msg = "hello from a satellite thread"

threads.Threads.serialization('threads.sharedserialize')

local x = {}
local xh = tds and tds.hash() or {}
local xs = {}
local z = tds and tds.hash() or {}
local D = 10
local K = tds and 100000 or 100  -- good luck in non-shared (30M)
for i=1,njob do
   x[i] = torch.ones(D)
   xh[i] = torch.ones(D)
   xs[i] = torch.FloatStorage(D):fill(1)
   for j=1,K do
      z[(i-1)*K+j] = "blah" .. i .. j
   end
end
collectgarbage()
collectgarbage()

print('GO')

local pool = threads.Threads(
   nthread,
   function(threadIdx)
      pcall(require, 'tds')
      print('starting a new thread/state number:', threadIdx)
      gmsg = msg -- we copy here an upvalue of the main thread
   end
)

local jobdone = 0
for i=1,njob do
   pool:addjob(
      function()
         assert(x[i]:sum() == D)
         assert(xh[i]:sum() == D)
         assert(torch.FloatTensor(xs[i]):sum() == D)
         for j=1,K do
            assert(z[(i-1)*K+j] == "blah" .. i .. j)
         end
         x[i]:add(1)
         xh[i]:add(1)
         torch.FloatTensor(xs[i]):add(1)
         print(string.format('%s -- thread ID is %x', gmsg, __threadid))
         collectgarbage()
         collectgarbage()
         return __threadid
      end,

      function(id)
         print(string.format("task %d finished (ran on thread ID %x)", i, id))
         jobdone = jobdone + 1
      end
   )
end

for i=1,njob do
   pool:addjob(
      function()
         collectgarbage()
         collectgarbage()
      end
   )
end

pool:synchronize()

print(string.format('%d jobs done', jobdone))

pool:terminate()

-- did we do the job in shared mode?
for i=1,njob do
   assert(x[i]:sum() == 2*D)
   assert(xh[i]:sum() == 2*D)
   assert(torch.FloatTensor(xs[i]):sum() == 2*D)
end

-- serialize and zero x
local str = torch.serialize(x)
local strh = torch.serialize(xh)
local strs = torch.serialize(xs)
for i=1,njob do
   x[i]:zero()
   xh[i]:zero()
   xs[i]:fill(0)
end

-- dude, check that unserialized x does not point on x
local y = torch.deserialize(str)
local yh = torch.deserialize(strh)
local ys = torch.deserialize(strs)
for i=1,njob do
   assert(y[i]:sum() == 2*D)
   assert(yh[i]:sum() == 2*D)
   assert(torch.FloatTensor(ys[i]):sum() == 2*D)
end

pool:terminate()

print('PASSED')
