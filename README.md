# dragon-farm

[![CRAN status](https://www.r-pkg.org/badges/version/dragonfarm)](https://CRAN.R-project.org/package=dragonfarm)
[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/tejas4patel/dragon-farm/blob/main/inst/remote/dragonfarm_remote.ipynb)

![dragonfarm: fine-tune a language model from R in minutes. Six steps: Data, Map, Model, Train, Monitor, Try it.](https://raw.githubusercontent.com/tejas4patel/dragon-farm/main/pkgdown/assets/banner.svg)

`dragonfarm` takes a table of prompts and replies, teaches a 100M to 3B parameter
model to answer in your format and your domain, and gives you back an adapter
or a merged model that loads with plain Hugging Face `transformers`. Training
runs in a background Python process that the package sets up for you, on your
own GPU or on a free cloud one.

![The app, step by step: load a table, drag columns into slots, pick a model, train, watch the loss, compare against the base model.](https://raw.githubusercontent.com/tejas4patel/dragon-farm/main/pkgdown/assets/demo/dragonfarm-demo.gif)

The app walks through six numbered steps, the same ones as in the GIF:

1. **Data**: load a table (CSV, TSV, JSON, JSONL, or Parquet, which needs the
   `arrow` package) or the example tickets.
2. **Map**: drag columns into the Prompt and Response slots.
3. **Model**: pick a base model and check your GPU.
4. **Train**: set a few numbers and press Start training, or send the run to a
   cloud GPU.
5. **Monitor**: watch the loss curve; the panel also shows the R code that
   reproduces the run.
6. **Try it**: compare the fine-tuned model with the base model, then judge,
   merge, or publish it.

## Install

```r
install.packages("dragonfarm")   # from CRAN
library(dragonfarm)
dragon_check()                   # first run builds the Python environment: 2 to 3 GB
```

The development version: `pak::pak("tejas4patel/dragon-farm")`. Then open the
app with `dragon_app()`.

## The same thing in code

```r
library(dragonfarm)
options(dragonfarm.runs_dir = "~/dragonfarm_runs")   # keep runs after R closes

run <- dragon_dataset(dragon_example_data()) |>
  dragon_map(prompt = "{subject}\n\n{body}", response = "reply") |>
  dragon_train("Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)

dragon_generate(run, "My thermostat keeps dropping off Wi-Fi.")
dragon_merge(run, "models/support-0.5b")
```

Runs live on disk, so you can close R and come back with
`dragon_run("~/dragonfarm_runs/<run id>")`, then `dragon_status()`,
`dragon_wait()`, `dragon_cancel()`, or `dragon_resume()`. By default a run goes
under a temporary folder that disappears when R closes, which is why the
example sets `dragonfarm.runs_dir` first (see `?dragon_runs_dir`).

## Before and after

`Qwen/Qwen2.5-0.5B-Instruct`, before and after fine-tuning on 190 of the
package's example support tickets (training takes about 2 to 4 minutes on a
laptop RTX 4060 and about 4 minutes on a free Colab T4, after the one-time
setup). This ticket was not in the training data; it is the median of the 10
held-out tickets by word overlap with the reference reply. Temperature 0:

> **Ticket:** Lumen bulb pack arrived damaged. Opened my Lumen bulb pack
> today and the casing is split. The packaging looked fine from the outside
> so it must have happened before shipping.

> **Base model:** I'm sorry to hear that your Lumen bulb pack has been
> damaged. It's important to take any damage seriously and report it to the
> manufacturer or seller as soon as possible. Here are some steps you can
> follow: 1. **Contact the Manufacturer**: Reach out to the company that sold
> you the Lumen bulb pack. They may be able to provide a replacement or offer
> a repair service. 2. **Report the Damage**: ... (shortened)

> **After fine-tuning:** I'm sorry your Lumen bulb pack arrived damaged. We
> will replace it at no cost. Please reply with a photo of the damage and one
> of the shipping label so we can file the carrier claim on our side. As soon
> as we have those, we ship a replacement Lumen bulb pack with a prepaid
> return label for the damaged unit. Usually a business day after the return
> is scanned in.

The policy and tone are right, but the last sentence mixes in a detail from
another ticket type (the real policy is two business days). That is typical of
small models, and a reason to review outputs before relying on them. The
example tickets are also synthetic and built from templates, so this shows a
model picking up a house style, not open-ended reliability. Measure on your own
data.

## Go further

| I want to | Read |
|---|---|
| Walk through the whole workflow | [Quickstart](https://dragonfarm.dev/articles/quickstart.html) |
| Use the app, or run it for other people | [The dragon-farm app](https://dragonfarm.dev/articles/shiny-app.html) |
| Train without a local GPU | [No GPU? Train in the cloud](https://dragonfarm.dev/articles/cloud-gpu.html) |
| Improve a model with judges, preference pairs, DPO | [Fine-tune, judge, prefer, repeat](https://dragonfarm.dev/articles/post-training-loop.html) |
| Train on rewards I can check (GRPO) | [Reinforcement learning](https://dragonfarm.dev/articles/reinforcement-learning.html) |
| Chat with a run and collect feedback | [Talk to it, anywhere it runs](https://dragonfarm.dev/articles/chat-and-feedback.html) |
| Measure whether it helped | [Metrics, judges, and comparisons](https://dragonfarm.dev/articles/evaluate.html) |
| Look up models, run files, and settings | [Requirements, models, and settings](https://dragonfarm.dev/articles/under-the-hood.html) |

## Requirements

R 4.1 or newer and about 3 GB of disk for the Python environment, which the
package sets up on first use. An NVIDIA GPU or Apple Silicon makes training
fast; the smallest models also run on a CPU. `dragon_check()` reports what it
found and how to fix it. Driver versions, GPU memory per model, and
environment variables are in
[Requirements, models, and settings](https://dragonfarm.dev/articles/under-the-hood.html).

## License

MIT. See [LICENSE.md](LICENSE.md).
