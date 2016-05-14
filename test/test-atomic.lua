local threads = require 'threads'
threads.Threads.serialization('threads.sharedserialize')

local status, tds = pcall(require, 'tds')
tds = status and tds or nil
if not status then return end

local atomic = tds.AtomicCounter()
local numOfThreads = 10

local pool = threads.Threads(numOfThreads)

local steps = 100000

for t=1,numOfThreads do
  pool:addjob(function()
    for i=1,steps do
      atomic:inc()
    end
  end)
end

pool:synchronize()

print(atomic)
assert(atomic:get() == numOfThreads * steps)

pool:terminate()

print('PASSED')