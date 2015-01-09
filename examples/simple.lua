local Threads = require 'threads'
local sdl = require 'sdl2'

local nthread = 4
local njob = 10
local msg = "hello from a satellite thread"

sdl.init(0)

local threads = Threads(
   nthread,
   function(threadIdx)
      gsdl = require 'sdl2'
   end,
   function(threadIdx)
      print('starting a new thread/state number:', threadIdx)
      gmsg = msg -- we copy here an upvalue of the main thread
   end
)

local jobdone = 0
for i=1,njob do
   threads:addjob(
      function()
         local id = tonumber(gsdl.threadID())
         print(string.format('%s -- thread ID is %x', gmsg, id))
         return id
      end,

      function(id)
         print(string.format("task %d finished (ran on thread ID %x)", i, id))
         jobdone = jobdone + 1 
      end
   )
end

threads:synchronize()

print(string.format('%d jobs done', jobdone))

threads:terminate()
