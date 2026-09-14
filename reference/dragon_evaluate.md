# Evaluate a finished run

Training already evaluates on the held-out rows and writes the result
into the run directory. This function reads that result, or recomputes
it with the saved adapter when `recompute = TRUE` or nothing was saved.

## Usage

``` r
dragon_evaluate(run, n_samples = 10, recompute = FALSE)
```

## Arguments

- run:

  A `dragon_run` or run directory.

- n_samples:

  Number of held-out prompts to generate replies for.

- recompute:

  Reload the model and evaluate again.

## Value

A list with `eval_loss`, `perplexity`, `eval_tokens`, and a `samples`
data frame with columns `prompt`, `reference`, `generated`.
