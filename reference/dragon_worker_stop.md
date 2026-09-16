# Stop the local inference worker

The local backend keeps a Python process alive with the last models
loaded. Call this to free the memory (GPU included). It restarts on the
next generation call.

## Usage

``` r
dragon_worker_stop()
```

## Value

`TRUE` invisibly.
