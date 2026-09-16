# Judge a run's replies with a language model

Two modes. With `against = NULL`, each reply is scored from 1 to 10
against a rubric, using the held-out reference answer as ground truth
when there is one. With `against` set, the run's replies are compared
pairwise with another model's replies to the same prompts, and the judge
picks a winner. Pairwise judging asks each question twice with the two
replies swapped, so a judge that favours whichever answer comes first
cannot bias the result.

## Usage

``` r
dragon_judge(
  x,
  against = NULL,
  prompts = NULL,
  n = 20,
  judge = NULL,
  rubric = NULL,
  system = NULL,
  max_new_tokens = 256,
  seed = 42
)
```

## Arguments

- x:

  A `dragon_run` or run directory whose replies are judged.

- against:

  What to compare with: `NULL` for scoring alone, `"base"` for the model
  the run started from (its base model, or the run it continued), or
  another run, model id, or model directory.

- prompts:

  Prompts to use. Defaults to `n` prompts from the run's held-out rows.

- n:

  How many held-out prompts to use when `prompts` is `NULL`.

- judge:

  The judge: a function taking a character vector of prompts and
  returning a character vector of replies, an `ellmer` chat object, or a
  Hugging Face model id or local model directory to use as a local
  judge. See
  [`dragon_judge_anthropic()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md)
  for the Claude API.

- rubric:

  What the judge should value. A sentence or two; a sensible default
  covers correctness, helpfulness, and following instructions.

- system:

  System prompt used when generating the replies being judged.

- max_new_tokens:

  Length cap for the generated replies.

- seed:

  Seed for sampling the held-out prompts.

## Value

A `dragon_judgement` object: a list with `mode`, `summary`, and
`details` (one row per prompt).

## Details

Prompts default to the run's held-out set, so scores are comparable
across runs that share a dataset. Results are written to `judge.json` in
the run directory and the summary is recorded in the run's status, where
[`dragon_compare()`](https://dragonfarm.dev/reference/dragon_compare.md)
picks it up.

## Examples

``` r
if (FALSE) { # \dontrun{
# Did preference optimization help? Compare the DPO run with the SFT run it started from.
j <- dragon_judge(dpo, against = "base", judge = dragon_judge_anthropic())
j$summary

# Absolute scores with a task-specific rubric.
dragon_judge(sft, rubric = "Reward replies that give concrete next steps and stay under 120 words.",
             judge = dragon_judge_anthropic(model = "claude-sonnet-5"))

# A local judge: any model dragon_generate() can load.
dragon_judge(sft, against = "base", judge = "Qwen/Qwen2.5-1.5B-Instruct")
} # }
```
