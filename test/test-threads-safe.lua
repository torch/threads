require 'torch'

if not (#arg == 0)
   and not (#arg == 1 and tonumber(arg[1]))
   and not (#arg == 2 and tonumber(arg[1]) and arg[2] == 'unsafe')
then
   error(string.format('usage: %s [number of runs] ["unsafe"]', arg[0]))
end

local N = tonumber(arg[1]) or 1000
local issafe = (arg[2] ~= 'unsafe')

local threads = require 'threads'

threads.Threads.serialization('threads.sharedserialize')

local tensor = torch.zeros(10000000)

local pool = threads.Threads(10)

local run =
   function()
      tensor:add(1)
   end

if issafe then
   run = threads.safe(run)
end

for i=1,N do
   pool:addjob(
      run,
      function()
         if i % (N/100) == 0 then
            io.write('.')
            io.flush()
         end
      end
   )
end

pool:synchronize()
print()

assert(tensor:min() == N)
assert(tensor:max() == N)

print('PASSED')
