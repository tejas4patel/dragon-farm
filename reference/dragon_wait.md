# Wait for a run to finish

Blocks with a progress bar until the run reaches a terminal state.

## Usage

``` r
dragon_wait(run, timeout = Inf, poll = 2)
```

## Arguments

- run:

  A `dragon_run`.

- timeout:

  Seconds to wait before giving up (the run keeps going).

- poll:

  Seconds between checks.

## Value

The run, invisibly. Errors if the run failed.
