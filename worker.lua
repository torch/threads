local sdl = require 'sdl2'
local ffi = require 'ffi'
local C = ffi.C

ffi.cdef[[

struct THCode {
  const char *data;
  int size;
};

struct THWorker {
  SDL_mutex *mutex;
  SDL_cond *notfull;
  SDL_cond *notempty;
  int head;
  int tail;
  int isempty;
  int isfull;
  int runningjobs;
  int maxjobs;
  char* serialize;
  int refcount;

  struct THCode *callbacks;
  struct THCode *args;
};
]]

local mt = {
   __index = {
      addjob =
         function(worker, callback, ...)
            local serialize = require(ffi.string(worker.serialize))

            sdl.lockMutex(worker.mutex)
            while worker.isfull == 1 do
               sdl.condWait(worker.notfull, worker.mutex)
            end

            local args = {...}
            worker.callbacks[worker.tail].data, worker.callbacks[worker.tail].size = serialize.save(callback)
            worker.args[worker.tail].data, worker.args[worker.tail].size = serialize.save(args)

            worker.tail = worker.tail + 1
            if worker.tail == worker.maxjobs then
               worker.tail = 0
            end
            if worker.tail == worker.head then
               worker.isfull = 1
            end
            worker.isempty = 0

            worker.runningjobs = worker.runningjobs + 1

            sdl.unlockMutex(worker.mutex)
            sdl.condSignal(worker.notempty)
         end,

      dojob =
         function(worker)
            local serialize = require(ffi.string(worker.serialize))

            sdl.lockMutex(worker.mutex)
            while worker.isempty == 1 do
               sdl.condWait(worker.notempty, worker.mutex)
            end
            local callback = serialize.load(worker.callbacks[worker.head].data, worker.callbacks[worker.head].size)
            local args = serialize.load(worker.args[worker.head].data, worker.args[worker.head].size)

            worker.head = worker.head + 1
            if worker.head == worker.maxjobs then
               worker.head = 0
            end
            if worker.head == worker.tail then
               worker.isempty = 1
            end
            worker.isfull = 0
            sdl.unlockMutex(worker.mutex)
            sdl.condSignal(worker.notfull)

            local res = {callback(unpack(args))} -- note: args is a table for sure

            sdl.lockMutex(worker.mutex)
            worker.runningjobs = worker.runningjobs - 1
            sdl.unlockMutex(worker.mutex)

            return unpack(res)
         end,

      retain =
         function(worker)
            sdl.lockMutex(worker.mutex)
            worker.refcount = worker.refcount + 1
            sdl.unlockMutex(worker.mutex)
         end,

      free =
         function(worker)
            sdl.lockMutex(worker.mutex)
            worker.refcount = worker.refcount - 1
            sdl.unlockMutex(worker.mutex)
            if worker.refcount == 0 then
               C.free(worker.serialize)
               C.free(worker.callbacks)
               C.free(worker.args)
               C.free(worker)
            end
         end,

      gc =
         function(worker)
            ffi.gc(worker, worker.free)
         end
   }
}

local __Worker = ffi.metatype("struct THWorker", mt)

local function Worker(N, serialize)
   serialize = serialize or 'threads.serialize'

   local worker = ffi.cast('struct THWorker*', C.malloc(ffi.sizeof('struct THWorker')))
   assert(worker ~= nil, 'could not allocate worker: out of memory')
   worker:gc()

   worker.refcount = 1
   worker.mutex = sdl.createMutex()
   worker.notfull = sdl.createCond()
   worker.notempty = sdl.createCond()
   worker.maxjobs = N
   worker.serialize = C.malloc(#serialize+1)
   ffi.copy(worker.serialize, serialize, #serialize)
   worker.serialize[#serialize] = 0

   worker.head = 0
   worker.tail = 0
   worker.isempty = 1
   worker.isfull = 0
   worker.runningjobs = 0

   worker.callbacks = C.malloc(ffi.sizeof('struct THCode')*N)
   worker.args = C.malloc(ffi.sizeof('struct THCode')*N)

   assert(worker.callbacks ~= nil, 'allocation errors for callback list')
   assert(worker.args ~= nil, 'allocation errors for argument list')

   return worker
end

return Worker
