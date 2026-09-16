# Preference optimization with DPO or ORPO

The second stage of post-training. Where
[`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md)
teaches a model what a good reply looks like, this teaches it which of
two replies is better, from a dataset mapped with
[`dragon_map_pairs()`](https://dragonfarm.dev/reference/dragon_map_pairs.md).

## Usage

``` r
dragon_prefer(
  dataset,
  model,
  method = c("dpo", "orpo"),
  beta = 0.1,
  lora = dragon_lora(),
  args = dragon_train_args(learning_rate = 5e-05, epochs = 2),
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

  A dataset mapped with
  [`dragon_map_pairs()`](https://dragonfarm.dev/reference/dragon_map_pairs.md).

- model:

  A Hugging Face model id such as
  `"HuggingFaceTB/SmolLM2-135M-Instruct"`, a local model directory, or a
  finished `dragon_run` to continue from. In the last case the earlier
  run's adapters are folded into the weights before this run adds its
  own, so stages chain: fine-tune, then `dragon_prefer()`, and so on.
  See
  [`dragon_presets()`](https://dragonfarm.dev/reference/dragon_presets.md)
  for model ids.

- method:

  `"dpo"` or `"orpo"`.

- beta:

  Preference strength. Typical values are 0.05 to 0.5.

- lora:

  LoRA settings from
  [`dragon_lora()`](https://dragonfarm.dev/reference/dragon_lora.md).

- args:

  Training settings. The defaults use a lower learning rate than
  [`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md),
  which preference methods need.

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

## Details

Two methods are available:

- `"dpo"`, Direct Preference Optimization. Pushes the model's implicit
  reward for the chosen reply above the rejected one, relative to a
  reference model. With LoRA the reference is the same model with the
  adapter switched off, so it costs no extra memory.

- `"orpo"`, Odds Ratio Preference Optimization. Combines the supervised
  loss on the chosen reply with an odds-ratio penalty on the rejected
  one. Needs no reference model and works from a base model that has not
  been fine-tuned yet.

`beta` controls how hard the model is pushed: the KL strength for DPO,
the odds-ratio weight for ORPO. `0.1` is a sensible start for both.

Pass a finished run as `model` to continue from it. Its adapters are
folded into the weights before this stage adds its own, which is the
usual sequence:
[`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md)
first, then `dragon_prefer()` on top.

## Examples

``` r
if (FALSE) { # \dontrun{
sft <- dragon_dataset("tickets.csv") |>
  dragon_map(prompt = "question", response = "answer") |>
  dragon_train("Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)

dpo <- dragon_dataset("preferences.csv") |>
  dragon_map_pairs(prompt = "question", chosen = "better", rejected = "worse") |>
  dragon_prefer(sft, method = "dpo", beta = 0.1, wait = TRUE)

dragon_evaluate(dpo)
dragon_generate(dpo, "My thermostat keeps dropping off Wi-Fi.")
} # }
```
