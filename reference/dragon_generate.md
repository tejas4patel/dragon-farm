# Generate replies from a fine-tuned model

Loads the model in a short-lived Python process, so each call pays a few
seconds of model-loading time. Pass several prompts at once to amortize
it.

## Usage

``` r
dragon_generate(
  x,
  prompt,
  system = NULL,
  max_new_tokens = 256,
  temperature = 0.7,
  top_p = 0.9,
  base = FALSE
)
```

## Arguments

- x:

  A `dragon_run`, a run directory, an adapter directory, a merged model
  directory, or a Hugging Face model id.

- prompt:

  One or more user prompts.

- system:

  Optional system prompt.

- max_new_tokens:

  Maximum tokens to generate per reply.

- temperature:

  Sampling temperature. `0` means greedy decoding.

- top_p:

  Nucleus sampling threshold.

- base:

  Ignore this run's adapter and generate from what it started with: the
  base model, or the earlier run it continued from. Useful for
  before-and-after comparisons.

## Value

A character vector, one reply per prompt.
