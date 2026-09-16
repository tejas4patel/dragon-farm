# Quickstart: fine-tune a small model from R

This walks through one complete fine-tune: a support-ticket dataset, a
135M parameter model that trains on a CPU in minutes, and a
before-and-after comparison. Swap in your own file and a bigger model
afterwards.

## 1. Check the machine

``` r

library(dragonfarm)
dragon_check()
```

The first call builds a Python environment with torch and transformers.
That is a 2 to 3 GB download and takes a few minutes. Later calls take a
second. The report tells you which device training will use. A CPU is
fine for the 135M and 360M models. Anything larger wants a GPU.

## 2. Load and map the data

A dataset is a table with one row per example. The bundled example has
`subject`, `body`, `product`, and `reply` columns.

``` r

ds <- dragon_dataset(dragon_example_data())
ds
```

[`dragon_map()`](https://dragonfarm.dev/reference/dragon_map.md) says
which columns form the user turn and the assistant turn. Each argument
is a column name or a template that combines columns.

``` r

ds <- dragon_map(ds,
  prompt = "{subject}\n\n{body}",
  response = "reply",
  system = "You are a support agent for a smart-home company. Be concrete and brief."
)
dragon_preview(ds, n = 1)
```

The system argument here is a constant. It could also be a column.

## 3. Train

``` r

run <- dragon_train(
  ds,
  model = "HuggingFaceTB/SmolLM2-135M-Instruct",
  lora = dragon_lora(r = 8, alpha = 16),
  args = dragon_train_args(epochs = 2, batch_size = 4, grad_accum = 2, max_seq_len = 512),
  wait = TRUE
)
```

With `wait = TRUE` you get a progress bar and the function returns when
training ends. Without it, the function returns at once and you poll:

``` r

run <- dragon_train(ds, "HuggingFaceTB/SmolLM2-135M-Instruct")
dragon_status(run)$state
tail(dragon_progress(run))
dragon_logs(run, 10)
dragon_wait(run)
```

Runs are directories under `dragonfarm_runs/`. They survive the R
session:

``` r

dragon_runs()
run <- dragon_run(dragon_runs()$dir[1])
```

## 4. Evaluate and try it

Training holds out 5 percent of rows and reports loss and perplexity on
them, plus a few generated replies next to the reference replies.

``` r

ev <- dragon_evaluate(run)
ev
ev$samples
```

Compare the tuned model with the base model on a fresh prompt:

``` r

prompt <- "Charged twice for Sentry doorbell\n\nMy card shows two charges for one order."
dragon_generate(run, prompt, temperature = 0)
dragon_generate(run, prompt, temperature = 0, base = TRUE)
```

## 5. Ship it

The adapter alone is small and loads with `peft`. For a standalone model
that needs neither peft nor dragonfarm, merge:

``` r

merged <- dragon_merge(run, "models/support-135m")
dragon_generate(merged, prompt)
```

To reproduce the run later, or share it, ask for the code:

``` r

cat(dragon_code(run))
```

## Choosing settings

- **Model.** Start with `HuggingFaceTB/SmolLM2-360M-Instruct` or
  `Qwen/Qwen2.5-0.5B-Instruct`. Move up only if quality is not enough.
- **Rank.** 8 to 16 is plenty for format and tone. Go to 32 or 64 when
  the model must learn a lot of new facts.
- **Learning rate.** `2e-4` for LoRA. Halve it if the loss curve is
  jagged.
- **Epochs.** 2 to 3. Watch the eval loss: if it rises while train loss
  keeps falling, you are overfitting.
- **Sequence length.** Set it just above your longest example. Shorter
  is faster and uses less memory.
- **Out of memory.** Lower `batch_size`, raise `grad_accum` to
  compensate, and turn on `gradient_checkpointing`.
