# Write fine-tuning data with a teacher model

Sends each prompt to a stronger model and keeps its replies as the
responses to train on. This is the fastest way to get good training data
for a small model: a few hundred prompts from your domain, answered the
way you want them answered. The result is saved as JSONL and returned as
a mapped dataset ready for
[`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md).

## Usage

``` r
dragon_synthesize(
  prompts,
  teacher,
  system = NULL,
  max_new_tokens = 512,
  temperature = 0.7,
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
  for prompts from an existing run.

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
reproduces runs trained on it.

## Examples

``` r
if (FALSE) { # \dontrun{
tickets <- dragon_dataset("tickets.csv") |>
  dragon_map(prompt = "{subject}\n\n{body}", response = "reply")
persona <- "You are a concise, warm support agent for a smart-home company."
teacher <- dragon_llm_anthropic(system = persona)
synth <- dragon_synthesize(tickets, teacher, system = persona)
run <- dragon_train(synth, "Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)
} # }
```
