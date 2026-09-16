# Import results trained on another machine

Copies the outputs of a run that trained elsewhere (through
[`dragon_remote()`](https://dragonfarm.dev/reference/dragon_remote.md))
back into the local run directory: the adapter, the status, the progress
log, the evaluation, and the sample generations. Afterwards
[`dragon_status()`](https://dragonfarm.dev/reference/dragon_status.md),
[`dragon_progress()`](https://dragonfarm.dev/reference/dragon_status.md),
[`dragon_evaluate()`](https://dragonfarm.dev/reference/dragon_evaluate.md),
[`dragon_generate()`](https://dragonfarm.dev/reference/dragon_generate.md),
and [`dragon_merge()`](https://dragonfarm.dev/reference/dragon_merge.md)
work as if the run had trained locally.

## Usage

``` r
dragon_import(run, results)
```

## Arguments

- run:

  A `dragon_run` or run directory.

- results:

  Path to the `dragonfarm-results-<run id>.zip` the notebook produced,
  or to a directory holding its unpacked contents.

## Value

The run, invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
dragon_import(run, "~/Downloads/dragonfarm-results-20260914-101500-qwen2-5-0-5b-instruct.zip")
} # }
```
