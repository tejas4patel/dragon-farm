# Reinforcement learning with verifiable rewards (GRPO)

The third stage of post-training. For every prompt the model writes
several completions, each is scored by the rewards, and the model is
nudged towards the completions that beat their group's average. A KL
penalty against the model it started from keeps it from drifting. This
is Group Relative Policy Optimization, the method behind recent
reasoning models, in its plain on-policy form.

## Usage

``` r
dragon_reinforce(
  dataset,
  model,
  rewards,
  group_size = 4,
  beta = 0.04,
  temperature = 1,
  max_new_tokens = 128,
  lora = dragon_lora(),
  args = dragon_train_args(learning_rate = 1e-05, epochs = 1, batch_size = 4, grad_accum
    = 1, save_steps = 20),
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
  [`dragon_map_prompts()`](https://dragonfarm.dev/reference/dragon_map_prompts.md).

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

- rewards:

  A
  [`dragon_reward()`](https://dragonfarm.dev/reference/dragon_reward.md)
  or a list of them.

- group_size:

  Completions sampled per prompt. 4 to 8 is typical; more gives a better
  baseline at more cost per step.

- beta:

  Weight of the KL penalty towards the starting model. Higher is more
  conservative.

- temperature:

  Sampling temperature for the completions. Must be above zero so the
  group varies.

- max_new_tokens:

  Length cap for each sampled completion.

- lora:

  LoRA settings from
  [`dragon_lora()`](https://dragonfarm.dev/reference/dragon_lora.md).

- args:

  Training settings. `batch_size` is prompts per step (so
  `batch_size * group_size` completions), `epochs` or `max_steps` set
  the length, and `save_steps` the checkpoint interval. The defaults use
  a small learning rate, which RL needs.

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

It works well when the reward is something you can check: a correct
number, valid JSON with the right keys, a required format, a length
budget, a test that passes. It works poorly as a substitute for
preference data on vague goals such as "be more helpful"; use
[`dragon_prefer()`](https://dragonfarm.dev/reference/dragon_prefer.md)
for those.

Pass a finished run as `model` to continue from it, which is the usual
order:
[`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md),
optionally
[`dragon_prefer()`](https://dragonfarm.dev/reference/dragon_prefer.md),
then this.

## Examples

``` r
if (FALSE) { # \dontrun{
math <- dragon_dataset("arithmetic.csv") |>
  dragon_map_prompts(prompt = "question", reference = "answer")
rl <- dragon_reinforce(
  math, sft,
  rewards = list(dragon_reward("numeric"), dragon_reward("length", max_chars = 300, weight = 0.2)),
  group_size = 6, wait = TRUE
)
dragon_evaluate(rl)     # mean reward on held-out prompts, per reward
} # }
```
