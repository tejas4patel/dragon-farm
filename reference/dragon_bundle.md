# Package a run for a cloud GPU

Writes a run directory exactly as
[`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md)
would, but instead of launching the trainer it zips everything a GPU
machine needs: the data in chat format, the configuration, the trainer's
Python code, and a notebook that runs it. Nothing is trained locally and
Python is not needed.

## Usage

``` r
dragon_bundle(
  dataset,
  model,
  lora = dragon_lora(),
  args = dragon_train_args(),
  name = NULL,
  run_dir = NULL,
  runs_dir = dragon_runs_dir(),
  n_samples = 10,
  revision = NULL,
  trust_remote_code = FALSE,
  method = NULL,
  beta = NULL,
  rewards = NULL,
  group_size = 4,
  temperature = 1,
  max_new_tokens = 128
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

- method:

  For a dataset mapped with
  [`dragon_map_pairs()`](https://dragonfarm.dev/reference/dragon_map_pairs.md),
  the preference method, `"dpo"` or `"orpo"`. Defaults to `"dpo"`.
  Ignored for prompt and response data.

- beta:

  Preference strength for `method`, or the KL weight for an RL run.
  Defaults to 0.1 and 0.04 respectively.

- rewards:

  For a dataset mapped with
  [`dragon_map_prompts()`](https://dragonfarm.dev/reference/dragon_map_prompts.md),
  the
  [`dragon_reward()`](https://dragonfarm.dev/reference/dragon_reward.md)
  list an RL run needs.

- group_size, temperature, max_new_tokens:

  RL sampling settings. See
  [`dragon_reinforce()`](https://dragonfarm.dev/reference/dragon_reinforce.md).

## Value

A `dragon_run` whose state is `"bundled"`.

## Details

Continue with
[`dragon_remote()`](https://dragonfarm.dev/reference/dragon_remote.md)
to open a provider and see the steps, and
[`dragon_import()`](https://dragonfarm.dev/reference/dragon_import.md)
to bring the results back into this run directory.

## Examples

``` r
if (FALSE) { # \dontrun{
run <- dragon_dataset(dragon_example_data()) |>
  dragon_map(prompt = "{subject}\n\n{body}", response = "reply") |>
  dragon_bundle("Qwen/Qwen2.5-0.5B-Instruct")
dragon_remote(run, "colab")
# ... train in the browser, download the results zip ...
dragon_import(run, "~/Downloads/dragonfarm-results-<run id>.zip")
dragon_generate(run, "My thermostat keeps dropping off Wi-Fi.")
} # }
```
