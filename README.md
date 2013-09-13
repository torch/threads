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
*   Job callback are fully serialized (including upvalues!), which allows a transparent copy of the data to any thread.
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
torch serialization system to adapt the package to its own needs. Soon
(with torch9), torch should be straighforward to install, so this
dependency should be minor too.

At this time, if you have torch7 installed:
```sh
torch-rocks install https://raw.github.com/andresy/sdl2-ffi/master/rocks/sdl2-scm-1.rockspec
torch-rocks install https://raw.github.com/andresy/threads-ffi/master/rocks/threads-scm-1.rockspec
```

If you do not have torch7 installed, well... wait for torch9, or try to install torch7.

# Usage #

