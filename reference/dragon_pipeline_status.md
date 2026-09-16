# Progress of a pipeline

Progress of a pipeline

## Usage

``` r
dragon_pipeline_status(x, runs_dir = dragon_runs_dir())
```

## Arguments

- x:

  A `dragon_pipeline` object or a pipeline id.

- runs_dir:

  Where the pipeline record lives, when `x` is an id.

## Value

The pipeline record as a list: `status`, `steps` (each with a state and,
when finished, a summary), and timestamps.
