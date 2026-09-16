# Write fine-tuning data with a teacher model

Sends each prompt to a stronger model and keeps its replies as the
responses to train on. This is the fastest way to get good training data
for a small model: a few hundred prompts from your domain, answered the
way you want them answered. A quality pass then drops rows that are too
short or too long, look garbled, repeat an earlier prompt, or repeat (or
nearly repeat) an earlier response, so a teacher's stock phrases don't
dominate the dataset. Passing a `judge` adds distillation with a quality
gate: it scores every surviving reply and keeps only the ones at or
above `min_score`, the way you would with a teacher answering a
student's own prompts (see
[`dragon_prompts()`](https://dragonfarm.dev/reference/dragon_prompts.md))
and filtering out its weaker answers. The result is saved as JSONL and
returned as a mapped dataset ready for
[`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md).

## Usage

``` r
dragon_synthesize(
  prompts,
  teacher,
  system = NULL,
  max_new_tokens = 512,
  temperature = 0.7,
  judge = NULL,
  min_score = 7,
  rubric = NULL,
  dedupe = TRUE,
  near_dup_threshold = 0.92,
  min_chars = 1,
  max_chars = Inf,
  min_alpha_ratio = 0,
  file = NULL,
  runs_dir = dragon_runs_dir(),
  name = "synthetic"
)
```

## Arguments

- prompts:

  A character vector of prompts, or a mapped `dragon_dataset` whose
  prompt template is rendered for every row. See
  [`dragon_prompts()`](https://dragonfarm.dev/reference/dragon_prompts.md)
  for prompts from an existing run, which is how distillation from "the
  model's own prompts" is done: pass `dragon_prompts(run, "train")`.

- teacher:

  The model that writes the replies:
  [`dragon_llm_anthropic()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md),
  an `ellmer` chat, a model id or directory, a finished run, or any
  function from prompts to replies.

- system:

  System prompt for the teacher. Also stored with every row so the
  student trains with the same instruction.

- max_new_tokens:

  Reply length cap for local teachers.

- temperature:

  Sampling temperature for local teachers.

- judge:

  Optional. Scores every surviving reply from 1 to 10 and drops the ones
  below `min_score`. See
  [`dragon_judge()`](https://dragonfarm.dev/reference/dragon_judge.md)
  for what is accepted.

- min_score:

  Minimum judge score to keep a reply. Only used when `judge` is given.

- rubric:

  What the judge should value. See
  [`dragon_judge()`](https://dragonfarm.dev/reference/dragon_judge.md).

- dedupe:

  Drop rows whose prompt repeats an earlier one, and rows whose response
  exactly or nearly repeats an earlier response (see
  `near_dup_threshold`).

- near_dup_threshold:

  Word-overlap similarity (0 to 1) above which two responses count as
  near-duplicates. Lower catches more; `1` disables near-duplicate
  detection while leaving exact-duplicate detection on.

- min_chars, max_chars:

  Keep only replies whose length in characters falls in this range.

- min_alpha_ratio:

  Minimum share of printable ASCII characters in a reply; a crude filter
  for garbled output or a reply in the wrong script. `0` (the default)
  disables it; non-English replies need it left off or set low.

- file:

  Where to write the JSONL. Defaults to a timestamped file under
  `synth/` in `runs_dir`.

- runs_dir:

  Parent directory for the default `file`.

- name:

  Label used in the default file name.

## Value

A `dragon_dataset` mapped with prompt and response columns (and system,
when given). The file path is its `source`, so
[`dragon_code()`](https://dragonfarm.dev/reference/dragon_code.md)
reproduces runs trained on it. `attr(ds, "synthesis")$dropped` breaks
down what the quality pass (and the judge, if used) removed.

## Examples

``` r
if (FALSE) { # \dontrun{
tickets <- dragon_dataset("tickets.csv") |>
  dragon_map(prompt = "{subject}\n\n{body}", response = "reply")
persona <- "You are a concise, warm support agent for a smart-home company."
teacher <- dragon_llm_anthropic(system = persona)
synth <- dragon_synthesize(tickets, teacher, system = persona)
run <- dragon_train(synth, "Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)

# Distill from the student's own prompts, keeping only replies a judge likes.
distilled <- dragon_synthesize(dragon_prompts(run, "train"), teacher,
                               judge = dragon_judge_anthropic(), min_score = 7)
} # }
```
