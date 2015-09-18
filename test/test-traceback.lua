local Threads = require 'threads'
Threads.serialization('threads.sharedserialize')

my_threads = Threads(1,
            function()
                -- nothing
            end)

my_threads:addjob(function()
    function evil_func()
        print('a'+1)
    end
    print("I'm doing fine")
    evil_func()
 end)

ok, res = pcall(my_threads.synchronize, my_threads)
assert(ok == false)
assert(res:find("in function 'evil_func'"))

my_threads:addjob(function()
    return 10
 end,
 function(x)
   assert(x == 10)
 end)

my_threads:synchronize()
