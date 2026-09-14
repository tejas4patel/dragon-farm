# Create a dataset for fine-tuning

Reads a file or wraps a data frame. Use
[`dragon_map()`](https://tejas4patel.github.io/dragon-farm/reference/dragon_map.md)
afterwards to say which columns hold the prompt and the response.

## Usage

``` r
dragon_dataset(x, ...)

# S3 method for class 'character'
dragon_dataset(x, format = NULL, name = NULL, ...)

# S3 method for class 'data.frame'
dragon_dataset(x, name = NULL, ...)
```

## Arguments

- x:

  A file path (CSV, TSV, JSONL, JSON array, or Parquet) or a data frame.

- ...:

  Passed to methods.

- format:

  One of `"csv"`, `"tsv"`, `"jsonl"`, `"json"`, or `"parquet"`. Inferred
  from the file extension when `NULL`.

- name:

  Display name. Defaults to the file name.

## Value

A `dragon_dataset` object.

## Examples

``` r
ds <- dragon_dataset(dragon_example_data())
ds
#> <dragon_dataset> support_tickets.jsonl: 200 rows, 6 columns
#> Columns: id <character>, product <character>, category <character>, subject
#> <character>, body <character>, reply <character>
#> Mapping: none yet. Call `dragon_map()`.
```
