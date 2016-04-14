local threads = require 'threads'

local nthread = 4
local njob = 100

local pool = threads.Threads(
   nthread,
   function(threadid)
      print('starting a new thread/state number ' .. threadid)
   end
)


local jobid = 0
local result -- DO NOT put this in get
local function get()
   
   -- fill up the queue as much as we can
   -- this will not block
   while jobid < njob and pool:acceptsjob() do
      jobid = jobid + 1
      
      pool:addjob(
         function(jobid)
            print(string.format('thread ID %d is performing job %d', __threadid, jobid))
            return string.format("job output from job %d", jobid)
         end,

         function(jobres)
            result = jobres
         end,

         jobid
      )
   end

   -- is there still something to do?
   if pool:hasjob() then
      pool:dojob() -- yes? do it!
      return result
   end

end

local jobdone = 0
repeat   
   -- get something asynchronously
   local res = get()
   
   -- do something with res (if any)
   if res then
      print(res)
      jobdone = jobdone + 1
   end
   
until not res -- until there is nothing remaining

assert(jobid == 100)
assert(jobdone == 100)

print('PASSED')

pool:terminate()
