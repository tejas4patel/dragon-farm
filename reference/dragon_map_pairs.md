# Map columns for preference optimization

For
[`dragon_prefer()`](https://dragonfarm.dev/reference/dragon_prefer.md).
Each row holds one prompt and two candidate replies: the one you prefer
and the one you want the model to move away from. As in
[`dragon_map()`](https://dragonfarm.dev/reference/dragon_map.md), each
argument is a column name or a
[`glue::glue()`](https://glue.tidyverse.org/reference/glue.html)
template combining several columns.

## Usage

``` r
dragon_map_pairs(dataset, prompt, chosen, rejected, system = NULL)
```

## Arguments

- dataset:

  A `dragon_dataset`.

- prompt:

  Column name or template for the user turn.

- chosen:

  Column name or template for the preferred reply.

- rejected:

  Column name or template for the reply to move away from.

- system:

  Optional column name or template for the system prompt. A template
  with no braces and no matching column is used as a constant system
  prompt for every row.

## Value

The dataset with the mapping attached.

## Examples

``` r
df <- data.frame(
  q = c("What is 2 + 2?", "Capital of France?"),
  good = c("4", "Paris"),
  bad = c("5", "Lyon")
)
ds <- dragon_map_pairs(dragon_dataset(df), prompt = "q", chosen = "good", rejected = "bad")
dragon_preview(ds, n = 1)
#> 
#> ── Row 1 
#> user:
#> What is 2 + 2?
#> chosen:
#> 4
#> rejected:
#> 5
```
