# The dragon-farm app

``` r

library(dragonfarm)
dragon_app()
```

The app is a thin client over the R functions. Nothing happens in the
app that you cannot do from the console, and every run it starts is a
normal run directory.

## The eight panels

**1 Data.** Drop a CSV, TSV, JSONL, JSON, or Parquet file on the input,
or click “Load the example tickets”. You see row and column counts and
the first eight rows.

**2 Map.** Choose the kind of data first: prompt and response rows for
fine-tuning, chosen and rejected pairs for preference optimization, or
prompts with an optional reference for reinforcement learning. The
columns appear as chips in the left bucket. Drag them into System,
Prompt, or Response. Two chips in one slot are joined with a blank line.
The template fields below fill in as you drag and can be edited by hand
for anything else, for example `Ticket #{id}: {subject}`. The right side
shows the first three rows exactly as the model will see them.

**3 Model.** Pick a preset or type a Hugging Face model id. “Detect
hardware” runs the same check as
[`dragon_check()`](https://dragonfarm.dev/reference/dragon_check.md) and
reports whether the chosen model fits in GPU memory and whether it needs
a token.

**4 Train.** Epochs, learning rate, rank, sequence length, and batch
size are on the front. Everything else is under Advanced. The stage
follows the data kind: preference pairs show the DPO or ORPO method and
beta, RL prompts show a reward builder. “Start from” continues from an
earlier run instead of a base model. The panel refuses to start until
the first three steps are complete, and estimates the number of
optimizer steps from your settings. “No GPU here?” packages the run for
a cloud GPU instead.

**5 Monitor.** A live loss curve with evaluation points (and mean reward
for RL runs), step count, ETA, the trainer log, and the R code for the
run. Cancel asks the trainer to stop after the current step and save.
Resume picks up from the last checkpoint. Every run in the runs
directory is listed, including ones started from the console. Below:
task metrics over the held-out rows, a comparison table of every run,
and import of results trained in the cloud.

**6 Try it.** Type a prompt and see the fine-tuned reply next to the
base model’s reply. Judge compares the run against what it started from
with a language model as referee. Improve samples the run’s own replies,
has the judge rank them, and loads the result as preference pairs for
the next stage. “Merge and save” writes a standalone model directory.

**7 Chat.** A conversation with memory: every turn sends the whole
history. Answer from a run on this machine, an Ollama model, or any
OpenAI-compatible server. Rate replies, edit them, or ask again;
[`dragon_feedback()`](https://dragonfarm.dev/reference/dragon_feedback.md)
turns those verdicts into training data. Save the transcript as JSON.

**8 Pipeline.** Runs the standard loop in a background R process:
fine-tune, sample and judge into pairs, DPO, judge again, metrics. Shows
each pipeline’s steps as they finish and the lineage of every run in the
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
[`dragon_generate()`](https://dragonfarm.dev/reference/dragon_generate.md),
which loads the model in a short-lived process, so each request takes a
few seconds.
