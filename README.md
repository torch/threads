Threads
=======

[![Build Status](https://travis-ci.org/torch/threads.svg)](https://travis-ci.org/torch/threads)

A thread package for Lua and LuaJIT.

The documentation for the _threads_ library is organized as follows
  * [Introduction](#intro)
  * [Installation](#install)
  * [Examples](#examples)
  * [Library](#library)

<a name="intro"/>

# Introduction #

Why another threading package for Lua, you might wonder?
Well, to my knowledge existing packages are quite limited: they create a new thread for a new given task, and then end the thread when the task ends.
The overhead related to creating a new thread each time I want to parallelize a task does not suit my needs.
In general, it is also very hard to pass data between threads.

The magic of the *threads* package lies in the seven following points:

  * Threads are created on demand (usually once in the program).
  * Jobs are submitted to the threading system in the form of a callback function. The job will be executed on the first free thread.
  * If provided, a ending callback will be executed in the main thread, when a job finishes.
  * Job callback are fully serialized (including upvalues!), which allows transparent copy of data to any thread.
  * Values returned by a job callback will be passed to the ending callback (serialized transparently).
  * As ending callbacks stay on the main thread, they can directly "play" with upvalues of the main thread.
  * Synchronization between threads is easy.

<a name="install"/>

# Installation #

`threads` relies on [Torch7](http://torch.ch) for serialization. It uses pthread,
and Windows thread implementation. One could easily get inspired from
Torch serialization system to adapt the package to its own needs. Torch
should be straighforward to install, so this dependency should be minor
too.

At this time, if you have torch7 installed, the installation can easily
achieved with luarocks:
```sh
luarocks install threads
```

<a name="examples"/>

# Examples #

A  [simple example](test/test-threads.lua) is better than convoluted explanations:

```lua
local threads = require 'threads'

local nthread = 4
local njob = 10
local msg = "hello from a satellite thread"


local pool = threads.Threads(
   nthread,
   function(threadid)
      print('starting a new thread/state number ' .. threadid)
      gmsg = msg -- get it the msg upvalue and store it in thread state
   end
)

local jobdone = 0
for i=1,njob do
   pool:addjob(
      function()
         print(string.format('%s -- thread ID is %x', gmsg, __threadid))
         return __threadid
      end,

      function(id)
         print(string.format("task %d finished (ran on thread ID %x)", i, id))
         jobdone = jobdone + 1
      end
   )
end

pool:synchronize()

print(string.format('%d jobs done', jobdone))

pool:terminate()
```

Typical output:

```sh
starting a new thread/state number 1
starting a new thread/state number 3
starting a new thread/state number 2
starting a new thread/state number 4
hello from a satellite thread -- thread ID is 1
hello from a satellite thread -- thread ID is 2
hello from a satellite thread -- thread ID is 1
hello from a satellite thread -- thread ID is 2
hello from a satellite thread -- thread ID is 4
hello from a satellite thread -- thread ID is 2
hello from a satellite thread -- thread ID is 1
hello from a satellite thread -- thread ID is 3
task 1 finished (ran on thread ID 1)
hello from a satellite thread -- thread ID is 4
task 2 finished (ran on thread ID 2)
hello from a satellite thread -- thread ID is 4
task 3 finished (ran on thread ID 1)
task 4 finished (ran on thread ID 2)
task 5 finished (ran on thread ID 4)
task 9 finished (ran on thread ID 4)
task 10 finished (ran on thread ID 4)
task 8 finished (ran on thread ID 3)
task 6 finished (ran on thread ID 2)
task 7 finished (ran on thread ID 1)
10 jobs done
```

## Advanced Example ##

See a neural network [threaded training example](benchmark/README.md) for a more advanced usage of `threads`.

<a name="library"/>

# Library #

The library provides different low-level and high-level threading capabilities.

  * [Mid-level](#threads.midlevel):
    * [Threads](#threads.main): a thread pool ;
    * [Queue](#queue): a thread-safe task queue ; and
    * [serialize](#threads.serialize): functions for serialization and deserialization.
    * [safe](#threads.safe): make a function thread-safe.
  * [Low-level](#threads.lowlevel):
    * [Thread](#thread): a single thread with no artifice ;
    * [Mutex](#mutex): a thread mutex ;
    * [Condition](#condition): a condition variable.
    * [Atomic counter](#atomic): lock free atomic counter

Soon some more high-level features will be proposed, built on top of Threads.

<a name='threads.midlevel'/>

## Threads Mid-Level Features

The mid-level feature of the `threads` package is the `threads.Threads()`
class, built upon low-level features. This class could be easily leveraged
to create higher-level abstractions.

<a name='threads.main'/>

### Threads ###

This class is used to manage a set of queue threads:
```lua
local threads = require 'threads'
local t = threads.Threads(4) -- create a pool of 4 threads
```

Note that in the past the `threads` package was providing only one class (`Threads`) and it was possible to do:
```lua
local Threads = require 'threads'
local t = Threads(4) -- create a pool of 4 threads
```
While this is still possible, the first (explicit) way is recommended for clarity, as more and more high-level classes will be added to `threads`.

Internally, a Threads instance uses several [Queues](#queue), i.e. thread-safe task queues:

  * `mainqueue` is used by the queue threads to communicate serialized `endcallback` functions back to the main thread; and
  * `threadqueue` is used by the main thread to communicate serialized `callback` function to the queue threads.
  * `threadspecificqueues` are used by the main thread to communicate serialized `callback` function to a specific thread.

Internally, the queue threads consist of an infinite loop that waits for
the next job to be available on the `threadqueue` queue.  The queue threads
can be switched from "specific" mode (in which case each thread i is
looking at jobs put in its specific `threadspecificqueues[i]` queue, or
non-specific mode (in which case, threads are looking at available jobs in
`threadqueue`. Specific and non-specific mode can be switched with [Threads:specific(boolean)](#threads.specific).

When a job is available, one of the threads executes it and returns the results back to the main thread via the `mainqueue` queue.
Upon receipt of the results, an optional `endcallback` is executed on the main thread (see [Threads:addjob()](#threads.addjob)).

There are no guarantee that all jobs are executed until [Threads:synchronize()](#threads.synchronize) is called.

Each thread has its own
[lua_State](http://www.lua.org/manual/5.1/manual.html#lua_State). However, we provide a [serialization](#threads.serialization)
scheme which allows automatic sharing for several Torch objects (storages,
tensors and tds types). Sharing of vanilla lua objects is not possible, but instances of classes that support serialization
(eg. [classic objects](https://github.com/deepmind/classic) with using `require 'classic.torch'` or those created with `torch.class`)
can be shared, but remember that only the memory in tensor storages and tds objects will be shared by the instances, other fields will be copies.
Also if synchronization is required that must be implemented by the user (ie. with `mutex`).


<a name='threads.Threads'/>

#### threads.Threads(N,[f1,f2,...]) ####

Argument `N` of this constructor specifies the number of queue threads that
will be spawned. The optional arguments `f1,f2,...` can be a list of
functions to execute in each queue thread.  To be clear, all of these
functions will be executed in each thread.  However, each optional function
`f` takes an argument `threadid` which is a number between `1` and `N`
identifying each thread.  This could be used to make each thread have
different behaviour.

Example:

```lua
threads.Threads(4,
   function(threadid)
      print("Initializing thread " .. threadid)
   end
)
```

Note that the id of each thread is also stored into the global variable `__threadid` (in each thread Lua state).  
Notice about Upvalues:  
When deserializing a callback, upvalues must be of known types. Since `f1,f2,...` in [threads.Threads()](#threads.Threads) are deserialized in order, we suggest that you make a separated `f1` containing all the definitions and put the other code in `f2,f3,...`. e.g.  
```
require 'nn'
local threads = require 'threads'
local model = nn.Linear(5, 10)
threads.Threads(
    2,
    function(idx)                       -- This code will crash
        require 'nn'                    -- because the upvalue 'model'
        local myModel = model:clone()   -- is of unknown type before deserialization
    end
)
```

```
require 'nn'
local threads = require 'threads'
local model = nn.Linear(5, 10)
threads.Threads(
    2,
    function(idx)                      -- This code is OK.
        require 'nn'
    end,                               -- child threads know nn.Linear when deserializing f2
    function(idx)
        local myModel = model:clone()  -- because f1 has already been executed
    end
)
```


<a name='threads.specific'/>

#### Threads:specific(boolean) ####

Switch the Threads system into specific (`true`) or non-specific (`false`) mode. In specific mode, one must provide the thread
index which is going to execute a given job (when calling [addjob()](#threads.addjob)). In non-specific mode, the first available thread
will execute the first available job.

Switching from specific to non-specific, or vice-versa, will first [synchronize](#threads.synchronize) the current running jobs.

<a name='threads.addjob'/>

#### Threads:addjob([id], callback, [endcallback], [...]) ####
This method is used to queue jobs to be executed by the pool of queue threads.

The `id` is the thread number that will be executing the given job. It *must* be passed in [specific](#threads.specific) mode, and is *absent* in non-specific mode.
The `callback` is a function that will be executed in each queue thread with the optional `...` arguments.
The `endcallback` is a function that will be executed in the main thread (the one calling this method). It defaults to `function() end`.

This method will return immediately, unless the [Queue](#queue) queue is full, in which case it will wait (i.e. block) until one of the queue threads retrieves a new job from the queue.

Before being executed in the queue thread, the `callback` and its optional `...` arguments are serialized by the main thread and unserialized by the queue. Other than through the optional arguments, the main thread can also transfer data to the queue by using upvalues:

```lua
local upvalue = 10
pool:addjob(
   function()
      queuevalue = upvalue
      return 1
   end,
   function(inc)
      upvalue = upvalue + inc
   end
)
```

In the above example, each queue thread will have a global variable `queuevalue` which will contain a copy of the main thread's `upvalue`.
Note that if the main thread's upvalue were global, as opposed to `local` it would not be an upvalue, and therefore would not be serialized along with the `callback`.
In which case, `queuevalue` would be `nil`.

In the same example, the queue also communicates a value to the main thread.
This is accomplished by having the `callback` return one ore many values which will be serialized and unserialized as arguments to the `endcallback` function.
In this case a value of `1` is received by the main thread as argument `inc` to the `endcallback` function, which then uses it to increment `upvalue`.
This demonstrates how communication between threads is easily achieved using the `addjob` method.

<a name='threads.dojob'/>

#### Threads:dojob() ####
This method is used to tell the main thread to execute the next `endcallback` in the queue (see [Threads:addjob](#threads.addjob)).
If no such job is available, the main thread of execution will wait (i.e. block) until the `mainthread` Queue (i.e. queue) is filled with a job.

In general, this method should not be called, except if one wants to use the [async capabilities](#threads.async) of the Threads class.
Instead, [synchronize()](#threads.synchronize) should be called to make sure all jobs are executed.

<a name='threads.synchronize'/>

#### Threads:synchronize() ####
This method will call [dojob](#threads.dojob) until all `callbacks` and corresponding `endcallbacks` are executed on the queue and main threads, respectively.
This method will also raise an error for any errors raised in the pool of queue threads.

<a name='threads.terminate'/>

#### Threads:terminate() ####
This method will call [synchronize](#threads.synchronize), terminate each queue and free their memory.

<a name='threads.serialization'/>

#### Threads.serialization(pkgname) ####
Specify which serialization scheme should be used. This function
should be called (if you want a particular serialization) before calling
[threads.Threads()](#threads.Threads) constructor.

A serialization package (`pkgname`) should return a table of serialization
functions when required (`save` and `load`). See
[serialize specifications](#threads.serialize) for more details.

By default the serialization system uses the `'threads.serialize'` sub-package, which leverages torch serialization.

The `'threads.sharedserialize'` sub-package is also provided, which transparently
*shares* the storages, tensors and [tds](http://github.com/torch/tds) C
data structures. This approach is great if one needs to pass large data
structures between threads. See
[the shared example](test/test-threads-shared.lua) for more details.

<a name='threads.acceptsjob'/>

#### Threads.acceptsjob([id]) ####

In [specific](#threads.specific) mode, `id` must be a number and the function will return `true` if the corresponding
thread queue is not full, `false` otherwise.

In [non-specific](#threads.specific) mode, `id` should not be passed, and
the function will return `true` if the global thread queue is not full,
`false` otherwise.

<a name='threads.hasjob'/>

#### Threads.hasjob() ####

Returns `true` if there are still some unfinished jobs running, `false` otherwise.

<a name='threads.async'/>

### Threads asynchronous mode ###

The methods [acceptsjob()](#threads.acceptsjob) and
[hasjob()](#threads.hasjob) allow you
to use the `threads.Threads` in an asynchronous manner, without the need of
calling [synchronize()](#threads.synchronize). See
[the asynchronous example](test/test-threads-async.lua) for a typical test
case.

<a name='queue'/>

### Queue ###
This class is in effect a thread-safe task queue. The class is returned upon requiring the sub-package:

```lua
Queue = require 'threads.queue'
```

#### Queue(N) ####
The Queue constructor takes a single argument `N` which specifies the maximum size of the queue.

<a name='queue.addjob'/>

#### Queue:addjob(callback, [...]) ####
This method is called by a thread to *put* a job in the queue.
The job is specified in the form of a `callback` function taking arguments `...`.
Both the `callback` function and `...` arguments are serialized before being *put* into the queue.
If the queue is full, i.e. it has more than `N` jobs, the calling thread will wait (i.e. block) until a job is retrieved by another thread.

<a name='queue.dojob'/>

#### [res] Queue:dojob() ####
This method is called by a thread to *get*, unserialize and execute a job inserted via [addjob](#queue.addjob) from the queue.
A calling thread will wait (i.e. block) until a new job can be retrieved.
It returns to the calller whatever the job function returns after execution.

<a name='threads.serialize'/>

### Serialize ###
A table of serialization functions is returned upon requiring the sub-package:

```lua
serialize = require 'threads.serialize'
```

<a name='threads.serialize.save'/>

#### [torch.CharStorage] serialize.save(func) ####
This function serializes function `func`.
It returns a torch `CharStorage`.


<a name='threads.serialize.load'/>

#### [obj] serialize.load(storage) ####
This function unserializes the outputs of a [serialize.save](#threads.serialize.save) (a `CharStorage`).
The unserialized object `obj` is returned.


<a name='threads.safe'/>

### threads.safe(func, [mutex]) ###

The function returns a new thread-safe function which embedds `func` (call
arguments and returned arguments are the same).  A mutex is created and
locked before the execution of `func()`, and unlocked after. The mutex is
destroyed at the garbage collection of `func`.

If needed, one can specify the `mutex` to use as a second optional argument
to threads.safe(). It is then up to the user to free this mutex when
needed.


<a name='threads.lowlevel'/>

## Threads Low-Level Features

Dive-in low-level features with the provided [example](test/test-low-level.lua).

### Thread ###

The `threads.Thread` class simply starts a thread, and executes a given Lua code in this thread.
It is up to the user to manage the event loop (if one is needed) to communicate with the thread.
The class `threads.Threads` is an built upon this class.

<a name='threads.thread'/>

#### threads.Thread(code) ####

Returns a thread id, and execute the code given as a string. The thread must be freed with [free()](#thread.free).

<a name='thread.free'/>

#### Thread:free(thread) ####

Wait for the given thread to finish, and free its resources.

### Mutex ###

Standard mutex.

<a name='threads.mutex'/>

#### thread.Mutex([id])

Returns a new mutex. If `id` is given, it must be a number returned by
another mutex with [id()](#mutex.id), in which case the returned mutex is
equivalent to the one uniquely referred by `id`.

A mutex must be freed with [free()](#mutex.free).

<a name='mutex.lock'/>

#### Mutex:lock() ####

Lock the given mutex. If a thread already locked the mutex, it will block until it has been unlock.

<a name='mutex.unlock'/>

#### Mutex:unlock() ####

Unlock the given mutex. This method call must follow a [lock()](#mutex.lock) call.

<a name='mutex.id'/>

#### Mutex:id() ####

Returns a number unambiguously representing the given mutex.

<a name='mutex.free'/>

#### Mutex:free() ####

Free given mutex.

### Condition ###

Standard condition variable.

<a name='threads.condition'/>

#### thread.Condition([id])

Returns a new condition variable. If `id` is given, it must be a number returned by
another condition variable with [id()](#condition.id), in which case the returned condition is
equivalent to the one uniquely referred by `id`.

A condition must be freed with [free()](#condition.free).

<a name='condition.id'/>

#### Condition:id() ####

Returns a number unambiguously representing the given condition.

<a name='condition.wait'/>

#### Condition:wait(mutex) ####

This function must be preceded by a `mutex:lock()` call.  Assuming the
mutex is locked, this method unlock it and wait until the condition signal
has been raised.

<a name='condition.unlock'/>

#### Condition.signal() ####

Raise the condition signal.

<a name='condition.free'/>

#### Condition.free() ####

Free given condition.

<a name ='atomic'>

### Atomic counter ###

`tds.AtomicCounter` has been implemented to be used with `sharedserialize` to provide fast and safe lockless counting of progress (steps) between threads. See [example](test/test-atomic.lua) for usage.
