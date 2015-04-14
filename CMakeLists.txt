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
)

add_torch_package(threads "${src}" "${luasrc}" "Threads")

target_link_libraries(threads luaT TH)

if(WIN32)
  add_definitions(-DUSE_WIN_THREADS=1)
else()
  set(CMAKE_THREAD_PREFER_PTHREAD)
  find_package(Threads REQUIRED)
  if(Threads_FOUND AND CMAKE_USE_PTHREADS_INIT)
    add_definitions(-DUSE_PTHREAD_THREADS=1)
    target_link_libraries(threads ${CMAKE_THREAD_LIBS_INIT})
  else()
    message(FATAL_ERROR "no threading system (pthread or Win32) available")
  endif()
endif()
