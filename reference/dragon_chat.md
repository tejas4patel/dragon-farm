# Talk to a model, with memory of the conversation

A conversation object that keeps the message history and sends all of it
on every turn, so the model has context. Works with any backend: the
local worker, Ollama, or a remote server. Transcripts use the same
message format as training data, so a good conversation can become an
example.

## Usage

``` r
dragon_chat(
  x = NULL,
  system = NULL,
  backend = dragon_backend(),
  max_new_tokens = 256,
  temperature = 0.7,
  top_p = 0.9,
  base = FALSE,
  runs_dir = dragon_runs_dir(),
  context_window = NULL
)

dragon_chat_load(path, x = NULL, backend = dragon_backend())
```

## Arguments

- x:

  What answers: a `dragon_run`, adapter or model directory, or model id.
  Ignored by server backends, which serve a fixed model.

- system:

  Optional system prompt, kept at the top of every turn.

- backend:

  Where to run inference. See
  [dragon_backend](https://dragonfarm.dev/reference/dragon_backend.md).

- max_new_tokens, temperature, top_p:

  Generation settings.

- base:

  Talk to what the run started from instead of the run.

- runs_dir:

  Where feedback from `$rate()` and `$edit()` is recorded (under
  `feedback/`). See
  [`dragon_feedback()`](https://dragonfarm.dev/reference/dragon_feedback.md).

- context_window:

  Approximate token budget for the conversation (system prompt plus
  history), such as a small model's 2K to 8K context. When the next turn
  would go over it, `$say()` drops the oldest user/assistant pair and
  tries again until it fits, keeping the system prompt and the most
  recent turns. `NULL` (the default) never drops turns. The token count
  is a rough estimate (about 4 characters per token), not the model's
  own tokenizer.

- path:

  A transcript written by `$save()`.

## Value

A `dragon_chat` object with methods: `$say(text, on_token = NULL)` sends
a user turn and returns the reply (streaming pieces to `on_token` when
the backend supports it); `$history()` returns the messages; `$reset()`
clears them; `$undo()` drops the last exchange; `$regenerate()` asks
again for the last reply; `$rate("up")` or `$rate("down")` records a
verdict on the last reply and `$edit(text)` replaces it with a better
one, both saved as feedback that
[`dragon_feedback()`](https://dragonfarm.dev/reference/dragon_feedback.md)
turns into training data; `$context_usage()` reports the estimated
tokens used, the window, and how many turns have been dropped to stay
under it (`NULL` when `context_window` is not set); `$save(path)` and
`dragon_chat_load(path)` write and read a transcript; `$as_example()`
returns the conversation as one training row.

## Examples

``` r
if (FALSE) { # \dontrun{
chat <- dragon_chat(run, system = "You are a concise support agent.")
chat$say("My thermostat keeps dropping off Wi-Fi.")
chat$say("I tried that. What else?")   # the model sees the first exchange
chat$history()
chat$save("good-conversation.json")
} # }
```
