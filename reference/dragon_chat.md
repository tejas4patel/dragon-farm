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
  base = FALSE
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

- path:

  A transcript written by `$save()`.

## Value

A `dragon_chat` object with methods: `$say(text, on_token = NULL)` sends
a user turn and returns the reply (streaming pieces to `on_token` when
the backend supports it); `$history()` returns the messages; `$reset()`
clears them; `$save(path)` and `dragon_chat_load(path)` write and read a
transcript; `$as_example()` returns the conversation as one training
row.

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
