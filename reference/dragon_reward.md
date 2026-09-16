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
    "custom"),
  weight = 1,
  name = NULL,
  pattern = NULL,
  case_sensitive = FALSE,
  keys = NULL,
  min_chars = NULL,
  max_chars = NULL,
  words = NULL,
  mode = c("any", "all"),
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
```
