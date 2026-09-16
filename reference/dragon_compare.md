# Compare runs side by side

One row per run with its stage, what it started from, and every number
the package knows about it: held-out loss, perplexity, preference
accuracy, task metrics from
[`dragon_evaluate()`](https://dragonfarm.dev/reference/dragon_evaluate.md),
and the latest judge result from
[`dragon_judge()`](https://dragonfarm.dev/reference/dragon_judge.md).
Runs that lack a measurement show `NA`.

## Usage

``` r
dragon_compare(..., runs_dir = dragon_runs_dir())
```

## Arguments

- ...:

  Runs, run directories, a single `dragon_pipeline` (its runs are
  compared), or nothing to list every run in `runs_dir`.

- runs_dir:

  Directory scanned when no runs are given.

## Value

A data frame of class `dragon_comparison`.

## Examples

``` r
if (FALSE) { # \dontrun{
dragon_compare()                 # everything in the runs directory
dragon_compare(sft, dpo)         # two specific runs
} # }
```
