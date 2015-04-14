local threads = {}

local C = require 'libthreads'

threads.Thread = C.Thread
threads.Mutex = C.Mutex
threads.Condition = C.Condition
threads.Threads = require 'threads.threads'

-- only for backward compatibility (boo)
setmetatable(threads, getmetatable(threads.Threads))

return threads
