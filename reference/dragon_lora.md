# LoRA settings

LoRA settings

## Usage

``` r
dragon_lora(r = 16, alpha = 32, dropout = 0.05, target_modules = "auto")
```

## Arguments

- r:

  Rank of the adapter matrices. Higher learns more, costs more memory.

- alpha:

  Scaling factor. A common rule is `alpha = 2 * r`.

- dropout:

  Dropout applied to the adapter input.

- target_modules:

  `"auto"` adapts every linear layer except the output head (peft's
  `"all-linear"`). Or a character vector of module names such as
  `c("q_proj", "v_proj")`.

## Value

A `dragon_lora` object.

## Examples

``` r
dragon_lora(r = 8, alpha = 16)
#> $r
#> [1] 8
#> 
#> $alpha
#> [1] 16
#> 
#> $dropout
#> [1] 0.05
#> 
#> $target_modules
#> [1] "auto"
#> 
#> attr(,"class")
#> [1] "dragon_lora"
```
