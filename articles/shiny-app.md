# The dragon-farm app

``` r

library(dragonfarm)
dragon_app()
```

The app is a thin client over the R functions. Nothing happens in the
app that you cannot do from the console, and every run it starts is a
normal run directory.

## The six panels

**1 Data.** Drop a CSV, TSV, JSONL, JSON, or Parquet file on the input,
or click “Load the example tickets”. You see row and column counts and
the first eight rows.

**2 Map.** The columns appear as chips in the left bucket. Drag them
into System, Prompt, or Response. Two chips in one slot are joined with
a blank line. The template fields below fill in as you drag and can be
edited by hand for anything else, for example `Ticket #{id}: {subject}`.
The right side shows the first three rows exactly as the model will see
them.

**3 Model.** Pick a preset or type a Hugging Face model id. “Detect
hardware” runs the same check as
[`dragon_check()`](https://tejas4patel.github.io/dragon-farm/reference/dragon_check.md)
and reports whether the chosen model fits in GPU memory and whether it
needs a token.

**4 Train.** Epochs, learning rate, rank, sequence length, and batch
size are on the front. Everything else is under Advanced. The panel
refuses to start until the first three steps are complete, and estimates
the number of optimizer steps from your settings.

**5 Monitor.** A live loss curve with evaluation points, step count,
ETA, the trainer log, and the R code for the run. Cancel asks the
trainer to stop after the current step and save. Resume picks up from
the last checkpoint. Every run in the runs directory is listed,
including ones started from the console.

**6 Try it.** Type a prompt and see the fine-tuned reply next to the
base model’s reply. “Merge and save” writes a standalone model
directory.

## Running it for other people

The app has to run on the machine with the GPU, and training runs as a
child process of the app. Shiny Server, Posit Connect, or a plain
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html) on a
workstation all work. Hosted services without GPUs, such as
shinyapps.io, can run the app but training will be CPU only.

Set the runs directory so every session sees the same runs:

``` r

dragon_app(runs_dir = "/srv/dragonfarm/runs", host = "0.0.0.0", port = 3838)
```

## Under the hood

The Map panel uses the `sortable` package for the drag-and-drop buckets.
Progress in the Monitor panel comes from polling `progress.jsonl` and
`status.json` once a second with `reactivePoll()`, so it works over a
remote connection and survives a browser refresh. The Try it panel calls
[`dragon_generate()`](https://tejas4patel.github.io/dragon-farm/reference/dragon_generate.md),
which loads the model in a short-lived process, so each request takes a
few seconds.
