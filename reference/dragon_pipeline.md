# Run several post-training stages as one pipeline

Executes the steps in order, threading the result of each into the next:
every training stage starts from the previous stage's run, synthesized
pairs feed the next preference stage, and judge and evaluate steps score
the latest run. Progress is written to `pipelines/<id>.json` under
`runs_dir` after every step, so a pipeline can be watched from the app
or another session with
[`dragon_pipeline_status()`](https://dragonfarm.dev/reference/dragon_pipeline_status.md).

## Usage

``` r
dragon_pipeline(
  model,
  steps,
  runs_dir = dragon_runs_dir(),
  name = "pipeline",
  background = FALSE
)
```

## Arguments

- model:

  Where the first training stage starts: a model id, a model directory,
  or a finished `dragon_run`.

- steps:

  A list of
  [dragon_step](https://dragonfarm.dev/reference/dragon_step.md)
  objects.

- runs_dir:

  Where runs and the pipeline record are written.

- name:

  Label used in the pipeline id.

- background:

  Run in a separate R process.

## Value

A `dragon_pipeline` object. In the foreground it holds the runs and
every step's summary; in the background it is a handle whose progress
[`dragon_pipeline_status()`](https://dragonfarm.dev/reference/dragon_pipeline_status.md)
reads.

## Details

With `background = TRUE` the pipeline runs in a separate R process and
the call returns at once. Steps must then be serializable: judges and
teachers made with
[`dragon_llm_anthropic()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md)
or plain functions are fine, `ellmer` chat objects are not.

## Examples

``` r
if (FALSE) { # \dontrun{
p <- dragon_pipeline("Qwen/Qwen2.5-0.5B-Instruct", list(
  dragon_step_train(tickets),
  dragon_step_synthesize_pairs(judge = dragon_judge_anthropic(model = "claude-sonnet-5")),
  dragon_step_prefer(),
  dragon_step_judge(judge = dragon_judge_anthropic())
), background = TRUE)
dragon_pipeline_status(p)
} # }
```
