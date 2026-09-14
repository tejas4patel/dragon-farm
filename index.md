# dragon-farm

Fine-tune small language models with LoRA from R, by code or by drag and
drop.

`dragonfarm` takes a table of prompts and replies, teaches a 100M to 3B
parameter model to answer in your format and your domain, and gives you
back an adapter or a merged model that loads with plain Hugging Face
`transformers`. Training runs in a background Python process that the
package sets up for you.

## Install

``` r

# install.packages("pak")
pak::pak("tejas4patel/dragon-farm")
```

Then check the machine. The first call builds a Python environment with
torch and transformers, which downloads 2 to 3 GB and takes a few
minutes.

``` r

library(dragonfarm)
dragon_check()
```

## Requirements

- **R 4.1 or newer.**
- **Disk:** about 3 GB for the Python environment, plus 0.3 to 4 GB per
  model in the Hugging Face cache.
- **Python:** nothing to install. `reticulate` uses a Python 3.10 to
  3.13 it finds on the machine, or downloads one. torch, transformers,
  and peft are installed automatically on first use.
- **GPU training on NVIDIA:** the only thing you install yourself is the
  NVIDIA driver, from
  [nvidia.com/drivers](https://www.nvidia.com/drivers). Driver 580 or
  newer gets the CUDA 13 build of torch, 570 or newer gets CUDA 12.8,
  and older drivers get CUDA 12.6. The CUDA Toolkit and cuDNN are not
  needed; torch wheels bundle their own CUDA libraries. Check your
  driver with `nvidia-smi`.
- **Apple Silicon:** trains on the GPU through Metal with no setup.
- **No GPU:** training runs on the CPU. Fine for the 135M and 360M
  models, slow beyond that.

Run
[`dragon_check()`](https://tejas4patel.github.io/dragon-farm/reference/dragon_check.md)
after installing. It reports the device it will train on, and if that is
the CPU on a machine with an NVIDIA GPU it says why (no driver, a driver
too old for the installed torch, or a CPU-only torch build) and prints
the one-line fix.

## The five-line version

``` r

library(dragonfarm)

run <- dragon_dataset(dragon_example_data()) |>
  dragon_map(prompt = "{subject}\n\n{body}", response = "reply") |>
  dragon_train("Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)

dragon_generate(run, "My thermostat keeps dropping off Wi-Fi.")
dragon_merge(run, "models/support-0.5b")
```

[`dragon_train()`](https://tejas4patel.github.io/dragon-farm/reference/dragon_train.md)
returns immediately by default. Runs live on disk, so you can close R
and come back:

``` r

run <- dragon_run("dragonfarm_runs/20260913-143201-qwen2.5-0.5b-instruct")
dragon_status(run)
dragon_progress(run)   # one row per logged step
dragon_wait(run)       # progress bar until it finishes
dragon_cancel(run)     # stops after the current step and saves a checkpoint
dragon_resume(run)     # picks up from that checkpoint
```

## The app

``` r

dragon_app()
```

Six panels, left to right: drop a file, drag its columns into Prompt and
Response slots, pick a model, set a few numbers, watch the loss curve,
and compare the tuned model against the base model. Every run started in
the app is a normal run directory, and the Monitor panel shows the R
code that reproduces it.

## What you get from a run

| File | Written by | Contents |
|----|----|----|
| `config.json` | R | Everything the trainer needs. |
| `data/train.jsonl`, `data/eval.jsonl` | R | Rows in chat format. |
| `status.json` | Python | State, device, parameter counts, final metrics. |
| `progress.jsonl` | Python | Loss, learning rate, and ETA per logging step. |
| `adapter/` | Python | The LoRA adapter, loadable with `peft`. |
| `checkpoints/` | Python | The last two checkpoints, for resume. |
| `eval.json`, `samples.json` | Python | Held-out loss and sample generations. |
| `merged/` | Python | After [`dragon_merge()`](https://tejas4patel.github.io/dragon-farm/reference/dragon_merge.md): a standalone model. |

## Models that work well

| Model | Size | License | Needs a token | Min GPU memory |
|----|----|----|----|----|
| `HuggingFaceTB/SmolLM2-135M-Instruct` | 135M | Apache 2.0 | no | 2 GB, or CPU |
| `HuggingFaceTB/SmolLM2-360M-Instruct` | 360M | Apache 2.0 | no | 3 GB |
| `Qwen/Qwen2.5-0.5B-Instruct` | 0.5B | Apache 2.0 | no | 3 GB |
| `google/gemma-3-1b-it` | 1B | Gemma | yes | 5 GB |
| `meta-llama/Llama-3.2-1B-Instruct` | 1.2B | Llama 3.2 | yes | 5 GB |
| `Qwen/Qwen2.5-1.5B-Instruct` | 1.5B | Apache 2.0 | no | 7 GB |
| `HuggingFaceTB/SmolLM2-1.7B-Instruct` | 1.7B | Apache 2.0 | no | 8 GB |

[`dragon_presets()`](https://tejas4patel.github.io/dragon-farm/reference/dragon_presets.md)
returns this table. Any other causal language model on the Hugging Face
Hub works too. For gated models, accept the license on the Hub and set
`HF_TOKEN` in the R session.

## How it works

R never imports torch. It writes a run directory and launches
`python -m dragonfarm.train` as a subprocess with `processx`. The
trainer is Hugging Face `transformers` with `peft` for LoRA and a
prompt-masking collator so only the reply tokens contribute to the loss.
Progress comes back through files, which is what lets the Shiny app poll
it and lets a run outlive the R session.

## Development

``` r

devtools::test()                                  # unit tests, no Python needed
Sys.setenv(DRAGONFARM_INTEGRATION = "true")
devtools::test(filter = "integration")            # trains SmolLM2-135M for 6 steps
```

The Python side has its own tests:
`PYTHONPATH=inst/python python inst/python/tests/run.py` (or
`python -m pytest inst/python/tests` if pytest is installed).

## Environment variables

| Variable | Effect |
|----|----|
| `DRAGONFARM_PYTHON` | Use this interpreter instead of the one reticulate builds. It must already have the packages from [`dragon_python_requirements()`](https://tejas4patel.github.io/dragon-farm/reference/dragon_python_requirements.md). |
| `DRAGONFARM_TORCH_INDEX` | Windows only. `auto` (default) selects the CUDA wheel index matching your NVIDIA driver on first Python use. Set to `""` to use PyPI’s CPU build, or to another index URL. |
| `DRAGONFARM_RUNS_DIR` | Where runs are stored. Default `dragonfarm_runs`. |
| `HF_TOKEN` | Hugging Face token for gated models. |
| `LLAMA_CPP_DIR` | A llama.cpp checkout, for [`dragon_export_gguf()`](https://tejas4patel.github.io/dragon-farm/reference/dragon_export_gguf.md). |

## License

MIT.
