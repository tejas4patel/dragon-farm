# Verifiable rewards for reinforcement learning

A reward scores one completion between 0 and 1.
[`dragon_reinforce()`](https://dragonfarm.dev/reference/dragon_reinforce.md)
takes one or more, sums them by `weight`, and pushes the model towards
higher totals. These built-ins are verifiable: they check facts about
the text rather than asking a model's opinion, which is what makes
reinforcement learning work on small models.

## Usage

``` r
dragon_reward(
  type = c("exact", "contains", "numeric", "regex", "json", "length", "keyword",
    "command", "custom"),
  weight = 1,
  name = NULL,
  pattern = NULL,
  case_sensitive = FALSE,
  keys = NULL,
  min_chars = NULL,
  max_chars = NULL,
  words = NULL,
  mode = c("any", "all"),
  command = NULL,
  input = c("stdin", "file"),
  score_from = c("exit_code", "stdout"),
  min_score = 0,
  max_score = 1,
  timeout = 30,
  file = NULL,
  fn = "reward"
)
```

## Arguments

- type:

  Which reward.

- weight:

  Multiplier when rewards are summed.

- name:

  Label used in progress rows and evaluation. Defaults to the type.

- pattern:

  Regular expression, for `"regex"`.

- case_sensitive:

  Whether `pattern` is case-sensitive.

- keys:

  Required top-level keys, for `"json"`.

- min_chars, max_chars:

  Bounds, for `"length"`. Give at least one.

- words:

  Words to look for, for `"keyword"`.

- mode:

  `"any"` or `"all"` of `words`.

- command:

  A character vector: the command and its arguments (run directly, not
  through a shell), for `"command"`.

- input:

  `"stdin"` or `"file"`, for `"command"`.

- score_from:

  `"exit_code"` (0 means 1.0, anything else 0.0) or `"stdout"` (the last
  number the command prints, rescaled from `min_score`/`max_score` and
  clamped to `0` to `1`), for `"command"`.

- min_score, max_score:

  Range that a `"stdout"` score is rescaled from, for `"command"`.

- timeout:

  Seconds before a `"command"` reward gives up and scores 0.

- file:

  Python file, for `"custom"`.

- fn:

  Name of the function inside `file`.

## Value

A `dragon_reward` object.

## Details

- `"exact"`: normalized exact match with the row's reference.

- `"contains"`: the reference appears in the completion.

- `"numeric"`: the last number in the completion equals the reference's.

- `"regex"`: the completion matches `pattern`.

- `"json"`: the completion is valid JSON, with `keys` present if given
  (partial credit per key).

- `"length"`: 1 within `min_chars` to `max_chars`, falling to 0 beyond.

- `"keyword"`: any (or all) of `words` appear.

- `"command"`: runs `command` and scores the completion by its exit code
  or its stdout. Common for code tasks: `command` a test suite or a
  linter. Never runs through a shell, so the completion's own text
  cannot inject anything into the command line: with `input = "stdin"`
  (the default) the completion is piped to the command's stdin; with
  `input = "file"` it is written to a temp file whose path replaces
  every `"{completion_file}"` token in `command`. This reward runs on
  whichever machine trains the run, so a cloud notebook needs `command`
  to be available there too.

- `"custom"`: a Python `file` defining
  `reward(prompt, completion, reference, row)` that returns a number.
  The file is copied into the run so the run stays self-contained.

## Examples

``` r
dragon_reward("exact")
#> <dragon_reward> exact (type exact, weight 1)
dragon_reward("regex", pattern = "^T-\\d{4}", weight = 2)
#> <dragon_reward> regex (type regex, weight 2; pattern = ^T-\d{4}, case_sensitive
#> = FALSE)
dragon_reward("length", max_chars = 400, weight = 0.5)
#> <dragon_reward> length (type length, weight 0.5; max_chars = 400)
dragon_reward("json", keys = c("id", "status"))
#> <dragon_reward> json (type json, weight 1; keys = id,status)
if (FALSE) { # \dontrun{
dragon_reward("command", command = c("pytest", "-q", "--tb=no"), input = "file")
} # }
```
