# Recommended base models

A table of instruction-tuned models that work well with LoRA on a single
consumer GPU, from a 135M model that trains on a CPU to a 7B that trains
in 4-bit on an 8 GB NVIDIA card. Any Hugging Face causal language model
id can be passed to
[`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md);
these are good starting points.

## Usage

``` r
dragon_presets()
```

## Value

A data frame with columns `id`, `params`, `license`, `gated`, `rank`,
`min_vram_gb`, `load_in_4bit` (whether it needs 4-bit loading to fit
`min_vram_gb`), and `notes`.

## Details

Which size to pick depends on the task. Measured on an 8 GB laptop GPU
(see the "Choosing a model size" article on the package website): for
answering from documents, writing training questions, or fine-tuning on
documents, use the 7B in 4-bit, or the 3B with less memory; models below
3B are wrong more often (untrained, the 0.5B on 14 of 55 test questions,
the 7B on none). For a fixed output format such as JSON fields or
labels, the 0.5B and 1.5B reach the same score as larger models in a few
minutes of training.

## Examples

``` r
dragon_presets()
#>                                    id params       license gated rank
#> 1 HuggingFaceTB/SmolLM2-135M-Instruct   135M    Apache 2.0 FALSE    8
#> 2 HuggingFaceTB/SmolLM2-360M-Instruct   360M    Apache 2.0 FALSE    8
#> 3          Qwen/Qwen2.5-0.5B-Instruct   0.5B    Apache 2.0 FALSE   16
#> 4                google/gemma-3-1b-it     1B         Gemma  TRUE   16
#> 5    meta-llama/Llama-3.2-1B-Instruct   1.2B     Llama 3.2  TRUE   16
#> 6          Qwen/Qwen2.5-1.5B-Instruct   1.5B    Apache 2.0 FALSE   16
#> 7 HuggingFaceTB/SmolLM2-1.7B-Instruct   1.7B    Apache 2.0 FALSE   16
#> 8            Qwen/Qwen2.5-3B-Instruct     3B Qwen Research FALSE   16
#> 9            Qwen/Qwen2.5-7B-Instruct     7B    Apache 2.0 FALSE   16
#>   min_vram_gb load_in_4bit
#> 1           2        FALSE
#> 2           3        FALSE
#> 3           3        FALSE
#> 4           5        FALSE
#> 5           5        FALSE
#> 6           7        FALSE
#> 7           8        FALSE
#> 8           5         TRUE
#> 9           8         TRUE
#>                                                                                                                  notes
#> 1                                                      Fastest. Trains on a CPU in minutes. Used by the package tests.
#> 2                                                                           Tiny. For trying the workflow on a laptop.
#> 3 App default. Fixed formats such as JSON: 20 of 20 after 3 minutes of training. Wrong on 14 of 55 document questions.
#> 4                                                                                          Needs a Hugging Face token.
#> 5                                                                                          Needs a Hugging Face token.
#> 6                                 Fixed formats and house style. Wrong on 6 of 55 document questions (the 7B on none).
#> 7                                          Largest of the small presets. Turn on gradient checkpointing on 8 GB cards.
#> 8            Documents on a smaller card: declines what the documents do not cover. Trains in 4-bit; research licence.
#> 9  Best for documents: answering, writing training questions, fine-tuning. 4-bit, batch size 1 on an 8 GB NVIDIA card.
```
