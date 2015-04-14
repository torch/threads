package = "threads"
version = "scm-1"

source = {
   url = "git://github.com/torch/threads-ffi.git"
}

description = {
   summary = "Threads for Torch",
   detailed = [[
Threading system for Torch. Relies on pthread (or Windows threads).
Transparent exchange of data between threads is allowed thanks to torch serialization.
   ]],
   homepage = "https://github.com/torch/threads-ffi",
   license = "BSD"
}

dependencies = {
   "lua >= 5.1",
   "torch >= 7.0",
}

build = {
   type = "cmake",
   variables = {
      CMAKE_BUILD_TYPE="Release",
      CMAKE_PREFIX_PATH="$(LUA_BINDIR)/..",
      CMAKE_INSTALL_PREFIX="$(PREFIX)"
   }
}
