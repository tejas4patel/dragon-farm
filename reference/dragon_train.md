# Fine-tune a model with LoRA

Writes a run directory, then launches the trainer as a background Python
process. Returns immediately unless `wait = TRUE`. The run survives the
R session; reopen it later with
[`dragon_run()`](https://dragonfarm.dev/reference/dragon_run.md).

## Usage

``` r
dragon_train(
  dataset,
  model,
  lora = dragon_lora(),
  args = dragon_train_args(),
  hardware = dragon_hardware(),
  name = NULL,
  run_dir = NULL,
  runs_dir = dragon_runs_dir(),
  n_samples = 10,
  revision = NULL,
  trust_remote_code = FALSE,
  wait = FALSE
)
```

## Arguments

- dataset:

  A mapped `dragon_dataset` (see
  [`dragon_map()`](https://dragonfarm.dev/reference/dragon_map.md)).

- model:

  A Hugging Face model id such as
  `"HuggingFaceTB/SmolLM2-135M-Instruct"`, a local model directory, or a
  finished `dragon_run` to continue from. In the last case the earlier
  run's adapters are folded into the weights before this run adds its
  own, so stages chain: fine-tune, then
  [`dragon_prefer()`](https://dragonfarm.dev/reference/dragon_prefer.md),
  and so on. See
  [`dragon_presets()`](https://dragonfarm.dev/reference/dragon_presets.md)
  for model ids.

- lora:

  LoRA settings from
  [`dragon_lora()`](https://dragonfarm.dev/reference/dragon_lora.md).

- args:

  Training settings from
  [`dragon_train_args()`](https://dragonfarm.dev/reference/dragon_train_args.md).

- hardware:

  Hardware settings from
  [`dragon_hardware()`](https://dragonfarm.dev/reference/dragon_hardware.md).

- name:

  Short label used in the run id. Defaults to the model name.

- run_dir:

  Exact directory to use. Defaults to a timestamped directory under
  `runs_dir`.

- runs_dir:

  Parent directory for runs. See
  [`dragon_runs_dir()`](https://dragonfarm.dev/reference/dragon_runs_dir.md).

- n_samples:

  Number of held-out rows to generate sample replies for at the end of
  training.

- revision:

  Model revision (branch, tag, or commit) on the Hub.

- trust_remote_code:

  Allow the model repository to run custom code.

- wait:

  Block until training finishes.

## Value

A `dragon_run` object.

## Examples

``` r
if (FALSE) { # \dontrun{
run <- dragon_dataset(dragon_example_data()) |>
  dragon_map(prompt = "{subject}\n\n{body}", response = "reply") |>
  dragon_train("HuggingFaceTB/SmolLM2-135M-Instruct", wait = TRUE)
dragon_generate(run, "My order arrived damaged.")
} # }
```
