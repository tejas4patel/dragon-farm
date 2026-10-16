# Hardware settings

Hardware settings

## Usage

``` r
dragon_hardware(
  device = c("auto", "cuda", "mps", "cpu"),
  dtype = c("auto", "bfloat16", "float16", "float32"),
  load_in_4bit = FALSE
)
```

## Arguments

- device:

  `"auto"` picks CUDA, then Apple MPS, then CPU. Or name one.

- dtype:

  `"auto"` picks bfloat16 on GPUs that support it, float16 on older
  GPUs, and float32 elsewhere.

- load_in_4bit:

  Load the base model in 4-bit through bitsandbytes. Only available on
  Linux with CUDA.

## Value

A `dragon_hardware` object.
