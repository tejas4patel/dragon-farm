# Training settings

Training settings

## Usage

``` r
dragon_train_args(
  epochs = 3,
  learning_rate = 2e-04,
  batch_size = 4,
  grad_accum = 4,
  max_seq_len = 1024,
  max_steps = NULL,
  warmup_ratio = 0.03,
  weight_decay = 0,
  logging_steps = 5,
  save_steps = 100,
  gradient_checkpointing = FALSE,
  seed = 42,
  ...
)
```

## Arguments

- epochs:

  Passes over the training data. Ignored when `max_steps` is set.

- learning_rate:

  Peak learning rate. `2e-4` is a good LoRA default.

- batch_size:

  Examples per device per step.

- grad_accum:

  Steps to accumulate before an optimizer update. Effective batch size
  is `batch_size * grad_accum`.

- max_seq_len:

  Maximum tokens per example. Longer examples are truncated.

- max_steps:

  Stop after this many optimizer steps. `NULL` trains for `epochs`.

- warmup_ratio:

  Fraction of steps used to warm up the learning rate.

- weight_decay:

  Weight decay for the optimizer.

- logging_steps:

  Steps between progress rows.

- save_steps:

  Steps between checkpoints.

- gradient_checkpointing:

  Trade compute for memory. Turn on if you run out of GPU memory.

- seed:

  Random seed.

- ...:

  Extra named arguments passed straight to `TrainingArguments`.

## Value

A `dragon_train_args` object.

## Examples

``` r
dragon_train_args(epochs = 1, learning_rate = 1e-4)
#> $epochs
#> [1] 1
#> 
#> $learning_rate
#> [1] 1e-04
#> 
#> $batch_size
#> [1] 4
#> 
#> $grad_accum
#> [1] 4
#> 
#> $max_seq_len
#> [1] 1024
#> 
#> $max_steps
#> NULL
#> 
#> $warmup_ratio
#> [1] 0.03
#> 
#> $weight_decay
#> [1] 0
#> 
#> $logging_steps
#> [1] 5
#> 
#> $save_steps
#> [1] 100
#> 
#> $gradient_checkpointing
#> [1] FALSE
#> 
#> $seed
#> [1] 42
#> 
#> $extra
#> named list()
#> 
#> attr(,"class")
#> [1] "dragon_train_args"
```
