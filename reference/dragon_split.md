# Hold out rows for evaluation

If you do not call this,
[`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md)
holds out 5 percent of rows (and none when the dataset has fewer than 20
rows).

## Usage

``` r
dragon_split(dataset, eval_frac = 0.05, seed = 42)
```

## Arguments

- dataset:

  A `dragon_dataset`.

- eval_frac:

  Fraction of rows to hold out.

- seed:

  Random seed for the split.

## Value

The dataset with the split attached.
