package = "threads"
version = "scm-1"

source = {
   url = "git://github.com/torch/threads-ffi.git"
}

description = {
   summary = "A FFI threading system",
   detailed = [[
A LuaJIT-based theading system. Relies on SDL2 threads for
portability. Transparent exchange of data between threads is allowed thanks
to torch serialization.
   ]],
   homepage = "https://github.com/torch/threads-ffi",
   license = "BSD"
}

dependencies = {
   "lua >= 5.1",
   "sdl2 >= 1.0",
   "torch >= 7.0",
}

build = {
   type = "builtin",
   modules = {
      ["threads.init"] = "init.lua",
      ["threads.worker"] = "worker.lua",
      ["threads.serialize"] = "serialize.lua"
   }      
}
