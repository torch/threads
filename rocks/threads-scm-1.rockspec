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
   type = "command",
   build_command = [[
cmake -E make_directory build && cd build && cmake .. -DLUALIB=$(LUALIB) -DLUA_INCDIR=$(LUA_INCDIR) -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(LUA_BINDIR)/.." -DCMAKE_INSTALL_PREFIX="$(PREFIX)" && $(MAKE)
   ]],
   platforms = {
      windows = {
         -- example with dlfcn-win
         -- luarocks make rocks\threads-scm-1.rockspec WIN_DLFCN_INCDIR="D:\Libraries\include" WIN_DLFCN_LIBDIR="D:\Libraries\lib"
         build_command = [[
cmake -E make_directory build && cd build && cmake .. -G "NMake Makefiles" -DWIN_DLFCN_INCDIR="$(WIN_DLFCN_INCDIR)" -DWIN_DLFCN_LIBDIR="$(WIN_DLFCN_LIBDIR)" -DLUALIB=$(LUALIB) -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(LUA_BINDIR)/.." -DCMAKE_INSTALL_PREFIX="$(PREFIX)" && $(MAKE)
]]
         -- example with dlfcn-win and pthread-win
         -- luarocks make rocks\threads-scm-1.rockspec WIN_DLFCN_INCDIR="D:\Libraries\include" WIN_DLFCN_LIBDIR="D:\Libraries\lib" CMAKE_HAVE_PTHREAD_H="D:\Libraries\include" CMAKE_HAVE_LIBC_CREATE="D:\Libraries\lib\pthreadVC2.lib" PTHREAD_LIB_NAME="pthreadVC2"
         -- build_command = [[
-- cmake -E make_directory build && cd build && cmake .. -G "NMake Makefiles" -DWIN_DLFCN_INCDIR="$(WIN_DLFCN_INCDIR)" -DWIN_DLFCN_LIBDIR="$(WIN_DLFCN_LIBDIR)" -DUSE_PTHREAD_THREADS=1 -DCMAKE_HAVE_PTHREAD_H="$(CMAKE_HAVE_PTHREAD_H" -DCMAKE_HAVE_LIBC_CREATE="$(CMAKE_HAVE_LIBC_CREATE)" -DPTHREAD_LIB_NAME="$(PTHREAD_LIB_NAME)" -DLUALIB=$(LUALIB) -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(LUA_BINDIR)/.." -DCMAKE_INSTALL_PREFIX="$(PREFIX)" && $(MAKE)
-- ]]
      }
   },
   install_command = "cd build && $(MAKE) install"
}
