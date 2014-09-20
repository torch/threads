# Benchmark #

This is a benchmark of the `threads` package, as well as a good real
use-case example, using Torch neural network packages.

Please install `torch7` with the neural network package `nn` before anything.

`benchmark-threaded.lua` compares to `benchmark.lua`, but parallelize over
examples in a batch.

Consider the following things:

  - The ideal number of threads might be larger than your number of
    cores. This is really task specific. Each core must be loaded as much
    as possible!

  - Deactivate OpenMP (even through libraries like MKL!) to avoid Torch
    OpenMP threaded code (like convolutions) or MKL threads to fight for
    cores with the threads created by the script! For e.g.,
```sh
export OMP_NUM_THREADS=1 # Torch threaded code and BLAS
export VECLIB_MAXIMUM_THREADS=1 # MacOS X veclib
```

  - Remember there is an overhead with threads (`benchmark.lua` is here to
    remember it to you), and that only large networks will be advantageous.

Good night, and good luck.
