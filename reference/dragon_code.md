# R code that reproduces a run

Every run, including ones started from the Shiny app, can be replayed as
a script. The dataset path is the original source when it was a file.

## Usage

``` r
dragon_code(run)
```

## Arguments

- run:

  A `dragon_run` or run directory.

## Value

A single string of R code.
