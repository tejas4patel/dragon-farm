# Push a run's model to the Hugging Face Hub

Uploads a run's model as a repo on the Hugging Face Hub, ready for any
hosted inference: a dedicated Inference Endpoint behind
[`dragon_backend_server()`](https://dragonfarm.dev/reference/dragon_backend.md),
`transformers-cli`, or any tool that loads a model by repo id. The repo
is created if it does not exist.

## Usage

``` r
dragon_publish(
  run,
  repo,
  what = c("merged", "adapter"),
  private = FALSE,
  commit_message = NULL
)
```

## Arguments

- run:

  A `dragon_run` or run directory.

- repo:

  A repo id, `"username/name"`.

- what:

  What to push. `"merged"` folds the adapter into the base model first
  (merging it if that has not been done yet), so the repo loads with
  plain transformers and needs neither `peft` nor dragonfarm; this is
  the usual choice for hosted inference. `"adapter"` pushes just the
  LoRA weights: a small, fast upload, but the base model and `peft` are
  needed to load it.

- private:

  Create the repo as private.

- commit_message:

  Defaults to a message naming the run and the stage.

## Value

The repo URL, invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
dragon_publish(run, "yourname/support-agent-0.5b")
dragon_publish(run, "yourname/support-agent-0.5b-adapter", what = "adapter")
} # }
```
