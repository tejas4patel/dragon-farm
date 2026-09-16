# Language models as functions: the Claude API and ellmer

Judges, teachers, and students in dragonfarm are plain functions from a
character vector of prompts to a character vector of replies. These
helpers build such functions.

## Usage

``` r
dragon_llm_anthropic(
  model = "claude-opus-5",
  system = NULL,
  api_key = Sys.getenv("ANTHROPIC_API_KEY"),
  max_tokens = 1024,
  max_active = 4,
  temperature = NULL
)

dragon_judge_anthropic(
  model = "claude-opus-5",
  api_key = Sys.getenv("ANTHROPIC_API_KEY"),
  max_tokens = 1024,
  max_active = 4
)

dragon_llm_ellmer(chat, system = NULL)

dragon_judge_ellmer(chat)
```

## Arguments

- model:

  Claude model id. The default is the most capable general model;
  `"claude-sonnet-5"` or `"claude-haiku-4-5"` are cheaper choices for
  large prompt sets.

- system:

  Optional system prompt.

- api_key:

  Anthropic API key.

- max_tokens:

  Reply length cap.

- max_active:

  How many requests to run at once.

- temperature:

  Sampling temperature, or `NULL` for the API default.

- chat:

  An `ellmer` chat object, for example
  [`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html).

## Value

A function suitable for the `judge`, `teacher`, or `student` arguments
of [`dragon_judge()`](https://dragonfarm.dev/reference/dragon_judge.md),
[`dragon_synthesize()`](https://dragonfarm.dev/reference/dragon_synthesize.md),
and
[`dragon_synthesize_pairs()`](https://dragonfarm.dev/reference/dragon_synthesize_pairs.md).

## Details

`dragon_llm_anthropic()` calls the Claude API directly over HTTP with
refusal fallbacks enabled, reading the key from `ANTHROPIC_API_KEY`.
`dragon_llm_ellmer()` wraps any `ellmer` chat, so every provider ellmer
supports works; each prompt gets a fresh copy of the chat so no history
leaks between questions. The `dragon_judge_*()` variants are the same
with a system prompt that asks for JSON-only answers, which
[`dragon_judge()`](https://dragonfarm.dev/reference/dragon_judge.md) and
[`dragon_synthesize_pairs()`](https://dragonfarm.dev/reference/dragon_synthesize_pairs.md)
need.

## Examples

``` r
if (FALSE) { # \dontrun{
teacher <- dragon_llm_anthropic(system = "You are a concise support agent.")
teacher(c("My thermostat drops off Wi-Fi.", "Invoice total looks wrong."))
} # }
```
