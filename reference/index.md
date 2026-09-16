# Package index

## Setup

- [`dragon_check()`](https://dragonfarm.dev/reference/dragon_check.md) :
  Check the Python environment and hardware
- [`dragon_python_requirements()`](https://dragonfarm.dev/reference/dragon_python_requirements.md)
  : Python requirements used by dragonfarm
- [`dragon_presets()`](https://dragonfarm.dev/reference/dragon_presets.md)
  : Recommended small models

## Data

- [`dragon_dataset()`](https://dragonfarm.dev/reference/dragon_dataset.md)
  : Create a dataset for fine-tuning
- [`dragon_map()`](https://dragonfarm.dev/reference/dragon_map.md) : Map
  dataset columns to prompt, response, and system text
- [`dragon_preview()`](https://dragonfarm.dev/reference/dragon_preview.md)
  : Preview mapped rows as chat turns
- [`dragon_split()`](https://dragonfarm.dev/reference/dragon_split.md) :
  Hold out rows for evaluation
- [`dragon_example_data()`](https://dragonfarm.dev/reference/dragon_example_data.md)
  : Path to the bundled example dataset

## Settings

- [`dragon_lora()`](https://dragonfarm.dev/reference/dragon_lora.md) :
  LoRA settings
- [`dragon_train_args()`](https://dragonfarm.dev/reference/dragon_train_args.md)
  : Training settings
- [`dragon_hardware()`](https://dragonfarm.dev/reference/dragon_hardware.md)
  : Hardware settings

## Training

- [`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md) :
  Fine-tune a model with LoRA
- [`dragon_resume()`](https://dragonfarm.dev/reference/dragon_resume.md)
  : Resume a run from its latest checkpoint
- [`dragon_wait()`](https://dragonfarm.dev/reference/dragon_wait.md) :
  Wait for a run to finish
- [`dragon_cancel()`](https://dragonfarm.dev/reference/dragon_cancel.md)
  : Cancel a run

## Runs

- [`dragon_run()`](https://dragonfarm.dev/reference/dragon_run.md) :
  Reopen an existing run
- [`dragon_runs()`](https://dragonfarm.dev/reference/dragon_runs.md) :
  List runs
- [`dragon_runs_dir()`](https://dragonfarm.dev/reference/dragon_runs_dir.md)
  : Directory where runs are stored
- [`dragon_status()`](https://dragonfarm.dev/reference/dragon_status.md)
  [`dragon_progress()`](https://dragonfarm.dev/reference/dragon_status.md)
  [`dragon_logs()`](https://dragonfarm.dev/reference/dragon_status.md) :
  Inspect a run
- [`dragon_code()`](https://dragonfarm.dev/reference/dragon_code.md) : R
  code that reproduces a run

## After training

- [`dragon_evaluate()`](https://dragonfarm.dev/reference/dragon_evaluate.md)
  : Evaluate a finished run
- [`dragon_generate()`](https://dragonfarm.dev/reference/dragon_generate.md)
  : Generate replies from a fine-tuned model
- [`dragon_merge()`](https://dragonfarm.dev/reference/dragon_merge.md) :
  Merge the adapter into the base model
- [`dragon_export_gguf()`](https://dragonfarm.dev/reference/dragon_export_gguf.md)
  : Export a merged model to GGUF

## Cloud GPUs

- [`dragon_bundle()`](https://dragonfarm.dev/reference/dragon_bundle.md)
  : Package a run for a cloud GPU
- [`dragon_remote()`](https://dragonfarm.dev/reference/dragon_remote.md)
  : Open a cloud GPU provider for a bundled run
- [`dragon_import()`](https://dragonfarm.dev/reference/dragon_import.md)
  : Import results trained on another machine
- [`dragon_remote_providers()`](https://dragonfarm.dev/reference/dragon_remote_providers.md)
  : Cloud GPU providers

## App

- [`dragon_app()`](https://dragonfarm.dev/reference/dragon_app.md) :
  Launch the dragon-farm app
