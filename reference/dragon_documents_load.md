# Reopen a saved document set

Reopen a saved document set

## Usage

``` r
dragon_documents_load(dir, runs_dir = dragon_runs_dir())
```

## Arguments

- dir:

  The set's directory, as printed by
  [`dragon_documents()`](https://dragonfarm.dev/reference/dragon_documents.md),
  or a set name under `runs_dir/documents/`.

- runs_dir:

  Where to look when `dir` is a bare name.

## Value

A `dragon_documents` object.
