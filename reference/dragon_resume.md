# Resume a run from its latest checkpoint

Useful after a cancel or a crash. Continues with the same configuration.

## Usage

``` r
dragon_resume(run, wait = FALSE)
```

## Arguments

- run:

  A `dragon_run`.

- wait:

  Block until training finishes.

## Value

A `dragon_run` object.
