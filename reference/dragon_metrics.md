# Task metrics for generated replies

Deterministic checks that need no judge model. Each metric is a function
of three character vectors, `generated`, `reference`, and `prompt`, and
returns one number per row (0 or 1 for pass/fail metrics). Pass names
from this list, or your own functions, to
[`dragon_evaluate()`](https://dragonfarm.dev/reference/dragon_evaluate.md).

## Usage

``` r
dragon_metrics()

dragon_metric_regex(pattern, ignore_case = TRUE)
```

## Arguments

- pattern:

  A regular expression the reply must match.

- ignore_case:

  Case-insensitive match.

## Value

`dragon_metrics()`: a named list of metric functions.

`dragon_metric_regex()`: a metric function.

## Details

- `exact`: normalized exact match (case, whitespace, and trailing
  punctuation ignored).

- `contains`: the normalized reference appears inside the reply.

- `token_f1`: token overlap F1 between reply and reference, the SQuAD
  style partial-credit score.

- `json_valid`: the reply parses as JSON (a fenced code block is
  unwrapped first).

- `numeric`: the last number in the reply equals the last number in the
  reference.

- `length_ratio`: characters in the reply divided by characters in the
  reference. Useful for spotting rambling or truncation.

`dragon_metric_regex()` builds a metric that passes when the reply
matches a pattern, for format checks such as "starts with a ticket id".

## Examples

``` r
m <- dragon_metrics()
m$exact("Paris.", "paris", "Capital of France?")
#> [1] 1
m$token_f1("the cat sat on the mat", "a cat sat on a mat", "")
#> [1] 0.6666667
m$json_valid('```json\n{"a": 1}\n```', "", "")
#> [1] 1
```
