cmake_minimum_required (VERSION 2.8)

set(CMAKE_MODULE_PATH
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake"
  "${CMAKE_MODULE_PATH}")

find_package(Torch REQUIRED)

set(src
  lib/init.c
  lib/THThread.c
)

set(luasrc
  init.lua
  threads.lua
  serialize.lua
  sharedserialize.lua
  queue.lua
  safe.lua
)

set(CMAKE_REQUIRED_INCLUDES ${LUA_INCDIR})
include(CheckCSourceCompiles)
check_c_source_compiles("
#include <lauxlib.h>
int main()
{
  long i = sizeof(&luaL_setfuncs);
  return 0;
}
" HAS_LUAL_SETFUNCS)
if(HAS_LUAL_SETFUNCS)
  add_definitions(-DHAS_LUAL_SETFUNCS)
endif()

ADD_LIBRARY(threadsmain MODULE lib/thread-main.c)
IF(APPLE)
  SET_TARGET_PROPERTIES(threadsmain PROPERTIES
    LINK_FLAGS "-undefined dynamic_lookup")
ENDIF()
INSTALL(TARGETS threadsmain LIBRARY DESTINATION "${Torch_INSTALL_LIB_SUBDIR}")

if(WIN32)
  link_directories(${LINK_DIRECTORIES} ${WIN_DLFCN_LIBDIR})
  include_directories(${INCLUDE_DIRECTORIES} ${WIN_DLFCN_INCDIR})
endif()

add_torch_package(threads "${src}" "${luasrc}" "Threads")
target_link_libraries(threads luaT TH)
if(WIN32)
  target_link_libraries(threads dl)
endif()

if(WIN32 AND (NOT DEFINED USE_PTHREAD_THREADS))
  add_definitions(-DUSE_WIN32_THREADS=1)
else()
  if(WIN32)
    add_definitions(-D_TIMESPEC_DEFINED=1)
  endif()
  set(CMAKE_THREAD_PREFER_PTHREAD)
  find_package(Threads REQUIRED)
  if(Threads_FOUND AND CMAKE_USE_PTHREADS_INIT)
    add_definitions(-DUSE_PTHREAD_THREADS=1)
    if(PTHREAD_LIB_NAME)
      target_link_libraries(threads ${PTHREAD_LIB_NAME})
    else()
      target_link_libraries(threads ${CMAKE_THREAD_LIBS_INIT})
    endif()
  else()
    message(FATAL_ERROR "no threading system (pthread or Win32) available")
  endif()
endif()

IF(LUALIB)
  TARGET_LINK_LIBRARIES(threads ${LUALIB})
  TARGET_LINK_LIBRARIES(threadsmain ${LUALIB})
ENDIF()
