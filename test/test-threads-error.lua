local threads = require 'threads'

local t = threads.Threads(1, function()
    sys = require 'sys'
end)

-- Trigger an error in an endcallback. The callback is run during lua_close
-- when the Threads:synchronize method is called from the __gc metamethod.
-- The error may prevent the thread from terminating before the threads module
-- and libthreads.so is unloaded. In previous versions of threads this would
-- cause a segfault.

t:addjob(function()
	sys.sleep(0.1)
end, function()
    error('error from callback')
end)
