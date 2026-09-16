# Open a cloud GPU provider for a bundled run

Prints the steps for running a bundled run on the chosen provider and,
by default in an interactive session, opens the provider in the browser
with the dragon-farm notebook loaded. Runs that were not bundled yet are
bundled first, so a run that failed locally for lack of memory can be
sent to the cloud as is.

## Usage

``` r
dragon_remote(
  run,
  provider = c("colab", "kaggle", "lightning", "runpod"),
  open = interactive()
)
```

## Arguments

- run:

  A `dragon_run` or run directory.

- provider:

  One of `"colab"`, `"kaggle"`, `"lightning"`, `"runpod"`. See
  [`dragon_remote_providers()`](https://dragonfarm.dev/reference/dragon_remote_providers.md).

- open:

  Open the provider link in the browser.

## Value

Invisibly, a list with `provider`, `url`, `bundle` (path to the zip),
and `steps` (a character vector).

## Examples

``` r
if (FALSE) { # \dontrun{
dragon_remote(run, "kaggle")
} # }
```
