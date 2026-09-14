# Reopen an existing run

Runs live entirely on disk, so any run can be picked up from a new R
session by its directory.

## Usage

``` r
dragon_run(dir)
```

## Arguments

- dir:

  Path to a run directory (one containing `config.json`).

## Value

A `dragon_run` object.
