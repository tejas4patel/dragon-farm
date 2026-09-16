# Build preference pairs from a model's own samples

Preference optimization needs, for each prompt, a better and a worse
reply. This function makes them without hand labelling, in one of two
ways:

## Usage

``` r
dragon_synthesize_pairs(
  prompts,
  student,
  judge = NULL,
  teacher = NULL,
  n_samples = 4,
  min_gap = 2,
  rubric = NULL,
  system = NULL,
  temperature = 0.8,
  max_new_tokens = 256,
  file = NULL,
  runs_dir = dragon_runs_dir(),
  name = "preferences"
)
```

## Arguments

- prompts:

  A character vector of prompts, or a mapped `dragon_dataset` whose
  prompt template is rendered for every row. See
  [`dragon_prompts()`](https://dragonfarm.dev/reference/dragon_prompts.md)
  for prompts from an existing run, which is how distillation from "the
  model's own prompts" is done: pass `dragon_prompts(run, "train")`.

- student:

  The model whose replies are being improved: normally the `dragon_run`
  you will continue from. Also a model id, ellmer chat, or function.

- judge:

  Scores the student's samples. See
  [`dragon_judge()`](https://dragonfarm.dev/reference/dragon_judge.md)
  for what is accepted. Required unless `teacher` is given.

- teacher:

  Writes the chosen reply instead of judging. See
  [`dragon_synthesize()`](https://dragonfarm.dev/reference/dragon_synthesize.md).

- n_samples:

  Samples per prompt in judge mode. At least 2.

- min_gap:

  Minimum score difference between chosen and rejected in judge mode.
  Pairs below it are dropped.

- rubric:

  What the judge should value. See
  [`dragon_judge()`](https://dragonfarm.dev/reference/dragon_judge.md).

- system:

  System prompt for the teacher. Also stored with every row so the
  student trains with the same instruction.

- temperature:

  Sampling temperature for the student. Needs to be above zero in judge
  mode, or every sample is the same.

- max_new_tokens:

  Reply length cap for local teachers.

- file:

  Where to write the JSONL. Defaults to a timestamped file under
  `synth/` in `runs_dir`.

- runs_dir:

  Parent directory for the default `file`.

- name:

  Label used in the default file name.

## Value

A `dragon_dataset` mapped as preference pairs. In judge mode the file
also records `chosen_score` and `rejected_score`.

## Details

- With a `judge`: the student answers each prompt `n_samples` times at a
  non-zero temperature, the judge scores every sample from 1 to 10, and
  the best and worst become the chosen and rejected replies. Prompts
  whose samples are too close (`min_gap`) or identical are dropped. This
  is the loop behind RLAIF-style training: the model improves on its own
  outputs under a judge's preferences.

- With a `teacher`: the teacher's reply is chosen and the student's is
  rejected. Cheap and effective when the teacher is clearly stronger.

The result is saved as JSONL and returned as a dataset mapped with
[`dragon_map_pairs()`](https://dragonfarm.dev/reference/dragon_map_pairs.md),
ready for
[`dragon_prefer()`](https://dragonfarm.dev/reference/dragon_prefer.md),
usually continuing from the student run itself.

## Examples

``` r
if (FALSE) { # \dontrun{
# Close the loop: sample from the fine-tuned run, let a judge rank, train DPO on the result.
pairs <- dragon_synthesize_pairs(dragon_prompts(sft, "train", n = 200), student = sft,
                                 judge = dragon_judge_anthropic(model = "claude-sonnet-5"))
dpo <- dragon_prefer(pairs, sft, wait = TRUE)
dragon_judge(dpo, against = "base", judge = dragon_judge_anthropic())
} # }
```
