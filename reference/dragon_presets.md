# Recommended small models

A table of small instruction-tuned models that work well with LoRA on a
single consumer GPU or, for the smallest, a CPU. Any Hugging Face causal
language model id can be passed to
[`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md);
these are just good starting points.

## Usage

``` r
dragon_presets()
```

## Value

A data frame with columns `id`, `params`, `license`, `gated`, `rank`,
`min_vram_gb`, and `notes`.

## Examples

``` r
dragon_presets()
#>                                    id params    license gated rank min_vram_gb
#> 1 HuggingFaceTB/SmolLM2-135M-Instruct   135M Apache 2.0 FALSE    8           2
#> 2 HuggingFaceTB/SmolLM2-360M-Instruct   360M Apache 2.0 FALSE    8           3
#> 3          Qwen/Qwen2.5-0.5B-Instruct   0.5B Apache 2.0 FALSE   16           3
#> 4                google/gemma-3-1b-it     1B      Gemma  TRUE   16           5
#> 5    meta-llama/Llama-3.2-1B-Instruct   1.2B  Llama 3.2  TRUE   16           5
#> 6          Qwen/Qwen2.5-1.5B-Instruct   1.5B Apache 2.0 FALSE   16           7
#> 7 HuggingFaceTB/SmolLM2-1.7B-Instruct   1.7B Apache 2.0 FALSE   16           8
#>                                                             notes
#> 1 Fastest. Trains on a CPU in minutes. Used by the package tests.
#> 2                                            Good laptop default.
#> 3                               App default. Strong for its size.
#> 4                                     Needs a Hugging Face token.
#> 5                                     Needs a Hugging Face token.
#> 6                   Top of the comfortable range on an 8 GB card.
#> 7   Largest preset. Turn on gradient checkpointing on 8 GB cards.
```
