# Python requirements used by dragonfarm

The package declares these with
[`reticulate::py_require()`](https://rstudio.github.io/reticulate/reference/py_require.html)
when it is loaded. You normally never call this yourself.

## Usage

``` r
dragon_python_requirements()
```

## Value

A list with `packages` (pip requirement strings) and `python_version`.

## Examples

``` r
dragon_python_requirements()
#> $packages
#> [1] "torch>=2.4"            "transformers>=4.46"    "peft>=0.13"           
#> [4] "accelerate>=1.0"       "safetensors>=0.4"      "numpy"                
#> [7] "sentencepiece"         "protobuf"              "huggingface_hub>=0.25"
#> 
#> $python_version
#> [1] ">=3.10,<3.14"
#> 
```
