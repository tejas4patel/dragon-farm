# Cloud GPU providers

Machines without a GPU can still fine-tune:
[`dragon_bundle()`](https://dragonfarm.dev/reference/dragon_bundle.md)
packages a run as a zip,
[`dragon_remote()`](https://dragonfarm.dev/reference/dragon_remote.md)
opens one of these providers with the dragon-farm notebook, and
[`dragon_import()`](https://dragonfarm.dev/reference/dragon_import.md)
brings the trained adapter back. Google Colab and Kaggle have free GPU
tiers. Lightning AI gives free monthly credits. RunPod is pay per hour.

## Usage

``` r
dragon_remote_providers()
```

## Value

A data frame with one row per provider: `provider` (the id to pass to
[`dragon_remote()`](https://dragonfarm.dev/reference/dragon_remote.md)),
`name`, `cost`, and `opens` (what the link opens).

## Examples

``` r
dragon_remote_providers()
#>    provider         name                                                cost
#> 1     colab Google Colab Free tier with a T4; paid tiers for longer sessions
#> 2    kaggle       Kaggle     Free: about 30 GPU hours a week (T4 x2 or P100)
#> 3 lightning Lightning AI            Free monthly credits, then pay as you go
#> 4    runpod       RunPod                   Pay per hour, wide choice of GPUs
#>                                        opens
#> 1         The dragon-farm notebook, directly
#> 2         The dragon-farm notebook, directly
#> 3 The dragon-farm repository in a new Studio
#> 4                         The RunPod console
```
