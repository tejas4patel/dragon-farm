# Map columns for reinforcement learning

For
[`dragon_reinforce()`](https://dragonfarm.dev/reference/dragon_reinforce.md).
Each row is a prompt the model will practise on, with an optional
reference answer that reward functions such as `"exact"` and `"numeric"`
compare against. Every other column travels along as `fields`, available
to custom reward functions.

## Usage

``` r
dragon_map_prompts(dataset, prompt, reference = NULL, system = NULL)
```

## Arguments

- dataset:

  A `dragon_dataset`.

- prompt:

  Column name or template for the user turn.

- reference:

  Optional column name or template for the reference answer.

- system:

  Optional column name or template for the system prompt. A template
  with no braces and no matching column is used as a constant system
  prompt for every row.

## Value

The dataset with the mapping attached.

## Examples

``` r
df <- data.frame(question = c("12 * 12?", "Capital of Peru?"), answer = c("144", "Lima"))
ds <- dragon_map_prompts(dragon_dataset(df), prompt = "question", reference = "answer")
dragon_preview(ds, n = 1)
#> 
#> ── Row 1 
#> user:
#> 12 * 12?
#> reference:
#> 144
```
