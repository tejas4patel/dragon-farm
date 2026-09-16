# Steps of a post-training pipeline

Each step becomes one stage of
[`dragon_pipeline()`](https://dragonfarm.dev/reference/dragon_pipeline.md).
Stages chain: a training step's run is the starting point of the next
training step, a synthesis step's pairs feed the next preference step,
judge and evaluate steps measure the most recent run, and a merge step
writes it out as a standalone model.

## Usage

``` r
dragon_step_train(dataset, lora = dragon_lora(), args = NULL, n_samples = 10)

dragon_step_prefer(
  dataset = NULL,
  method = c("dpo", "orpo"),
  beta = 0.1,
  lora = dragon_lora(),
  args = NULL,
  n_samples = 10
)

dragon_step_synthesize_pairs(
  prompts = "train",
  n = 100,
  judge = NULL,
  n_samples_per_prompt = 4,
  min_gap = 2,
  rubric = NULL,
  temperature = 0.8,
  max_new_tokens = 256
)

dragon_step_reinforce(
  dataset,
  rewards,
  group_size = 4,
  beta = 0.04,
  temperature = 1,
  max_new_tokens = 128,
  lora = dragon_lora(),
  args = NULL,
  n_samples = 10
)

dragon_step_judge(against = "base", judge = NULL, n = 20, rubric = NULL)

dragon_step_evaluate(metrics = TRUE)

dragon_step_merge(out = NULL)
```

## Arguments

- dataset:

  A mapped dataset for the stage. `dragon_step_prefer()` may leave it
  `NULL` to use the pairs made by the preceding
  `dragon_step_synthesize_pairs()`.

- lora, args, n_samples:

  As in
  [`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md).
  `args = NULL` uses the stage's own defaults.

- method, beta:

  As in
  [`dragon_prefer()`](https://dragonfarm.dev/reference/dragon_prefer.md).

- prompts:

  `"train"` or `"eval"` to take prompts from the current run's data, or
  a character vector or mapped dataset.

- n:

  How many prompts to use.

- judge, rubric:

  As in
  [`dragon_judge()`](https://dragonfarm.dev/reference/dragon_judge.md).

- n_samples_per_prompt, min_gap, temperature, max_new_tokens:

  As in
  [`dragon_synthesize_pairs()`](https://dragonfarm.dev/reference/dragon_synthesize_pairs.md).

- rewards, group_size:

  As in
  [`dragon_reinforce()`](https://dragonfarm.dev/reference/dragon_reinforce.md).

- against:

  As in
  [`dragon_judge()`](https://dragonfarm.dev/reference/dragon_judge.md).

- metrics:

  As in
  [`dragon_evaluate()`](https://dragonfarm.dev/reference/dragon_evaluate.md).

- out:

  As `out_dir` in
  [`dragon_merge()`](https://dragonfarm.dev/reference/dragon_merge.md):
  where the merged model goes; `NULL` means `merged/` inside the run.

## Value

A `dragon_step` object.

## Examples

``` r
if (FALSE) { # \dontrun{
steps <- list(
  dragon_step_train(tickets),
  dragon_step_synthesize_pairs(prompts = "train", n = 150, judge = dragon_judge_anthropic()),
  dragon_step_prefer(),
  dragon_step_judge(against = "base", judge = dragon_judge_anthropic()),
  dragon_step_evaluate(metrics = c("token_f1", "length_ratio"))
)
p <- dragon_pipeline("Qwen/Qwen2.5-0.5B-Instruct", steps)
dragon_compare(p)
} # }
```
