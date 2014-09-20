Threads
=======

# Introduction #

Why another threading package for Lua, you might wonder? Well, to my
knowledge existing packages are quite limited: they create a new thread for
a new given task, and then end the thread when the task ends. The overhead
related to creating a new thread each time I want to parallelize a task
does not suit my needs. In general, it is also very hard to pass data
between threads.

The magic of the *threads* package lies in the seven following points:
*   Threads are created on demand (usually once in the program).
*   Jobs are submitted to the threading system in the form of a callback function. The job will be executed on the first free thread.
*   An ending callback will be executed in the main thread, when a job finishes.
*   Job callback are fully serialized (including upvalues!), which allows transparent copy of data to any thread.
*   Values returned by a job callback will be passed to the ending callback (serialized transparently).
*   As ending callbacks stay on the main thread, they can directly "play" with upvalues of the main thread.
*   Synchronization between threads is easy.

# Installation #

At this time *threads* relies on two other packages: *torch* (for
serialization) and *SDL2* for threads.

One could certainly port easily this package to other threading API
(pthreads, Windows threads...), but as SDL2 is really easy to install, and
very portable, I believe this dependency should not be a problem. If there
are enough requests, I might propose alternatives to SDL2 threads.

Torch is used for full serialization. One could easily get inspired from
Torch serialization system to adapt the package to its own needs. Soon
(with torch9), Torch should be straighforward to install, so this
dependency should be minor too.

At this time, if you have torch7 installed:
```sh
luarocks install https://raw.github.com/torch/sdl2-ffi/master/rocks/sdl2-scm-1.rockspec
luarocks install https://raw.github.com/torch/threads-ffi/master/rocks/threads-scm-1.rockspec
```

# Example Usage #

An example is better than convoluted explanations.

```lua
local Threads = require 'threads'
local sdl = require 'sdl2'

local nthread = 4
local njob = 10
local msg = "hello from a satellite thread"

-- init SDL (follow your needs)
sdl.init(0)

-- init the thread system
-- one lua state is created for each thread

-- the function takes several callbacks as input, which will be executed
-- sequentially on each newly created lua state
local threads = Threads(nthread,
                        -- typically the first callback requires modules
                        -- necessary to serialize other callbacks
                        function()
                           gsdl = require 'sdl2'
                        end,

                        -- other callbacks (one is enough in general!) prepare stuff
                        -- you need to run your program
                        function()
                           print('starting a new thread/state')
                           gmsg = msg -- we copy here an upvalue of the main thread
                        end)

-- now add jobs
local jobdone = 0
for i=1,njob do
   threads:addjob(
                  -- the job callback
                  function()
                     local id = tonumber(gsdl.threadID())
                     print(string.format('%s -- thread ID is %x', gmsg, id))

                     -- return a value to the end callback
                     return id
                  end,

                  -- the end callback
                  -- ran in the main thread
                  function(id)
                     print(string.format("task %d finished (ran on thread ID %x)", i, id))

                     -- note that we can manipulate upvalues of the main thread
                     -- as this callback is ran in the main thread!
                     jobdone = jobdone + 1 
                  end)
end

-- wait for all jobs to finish
threads:synchronize()

print(string.format('%d jobs done', jobdone))

-- of course, one can run more jobs if necessary!

-- terminate threads
threads:terminate()
```

Typical output:

```sh
starting a new thread/state
starting a new thread/state
starting a new thread/state
starting a new thread/state
hello from a satellite thread -- thread ID is cd24000
hello from a satellite thread -- thread ID is cec8000
hello from a satellite thread -- thread ID is d06c000
hello from a satellite thread -- thread ID is cd24000
task 1 finished (ran on thread ID cd24000)
hello from a satellite thread -- thread ID is d210000
task 2 finished (ran on thread ID cec8000)
task 3 finished (ran on thread ID d06c000)
task 4 finished (ran on thread ID cd24000)
task 5 finished (ran on thread ID d210000)
hello from a satellite thread -- thread ID is cec8000
hello from a satellite thread -- thread ID is d06c000
hello from a satellite thread -- thread ID is cd24000
task 6 finished (ran on thread ID cec8000)
hello from a satellite thread -- thread ID is d210000
hello from a satellite thread -- thread ID is cec8000
task 7 finished (ran on thread ID d06c000)
task 8 finished (ran on thread ID cd24000)
task 9 finished (ran on thread ID d210000)
task 10 finished (ran on thread ID cec8000)
10 jobs done
```
