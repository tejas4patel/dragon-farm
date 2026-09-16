# Multi-turn conversations as training data

[`dragon_map()`](https://dragonfarm.dev/reference/dragon_map.md) builds
one user turn and one assistant turn per row. When the examples are
whole conversations, chat transcripts for instance, use this instead.
Each conversation is a list of messages with `role` and `content`; it
must contain at least one user turn and end with an assistant turn,
which is the turn the model learns to produce. Earlier turns are
context.

## Usage

``` r
dragon_conversations(x, name = NULL)
```

## Arguments

- x:

  A list of conversations (each a list of messages), a path to a JSONL
  file with one `{"messages": [...]}` object per line, or a data frame
  with a `messages` list column.

- name:

  Display name. Defaults to the file name.

## Value

A `dragon_dataset` mapped as conversations, usable wherever a prompt and
response dataset is:
[`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md),
[`dragon_bundle()`](https://dragonfarm.dev/reference/dragon_bundle.md),
[`dragon_step_train()`](https://dragonfarm.dev/reference/dragon_step.md).

## Examples

``` r
convs <- list(
  list(
    list(role = "system", content = "You are a support agent."),
    list(role = "user", content = "My thermostat drops off Wi-Fi."),
    list(role = "assistant", content = "Which router do you use?"),
    list(role = "user", content = "An Eero."),
    list(role = "assistant",
         content = "Eero often band-steers 2.4 GHz devices. Make a 2.4 GHz-only network.")
  )
)
ds <- dragon_conversations(convs)
dragon_preview(ds)
#> 
#> ── Row 1 
#> system:
#> You are a support agent.
#> user:
#> My thermostat drops off Wi-Fi.
#> assistant:
#> Which router do you use?
#> user:
#> An Eero.
#> assistant:
#> Eero often band-steers 2.4 GHz devices. Make a 2.4 GHz-only network.
```
