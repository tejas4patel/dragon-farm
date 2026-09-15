# dragonfarm (development version)

* `dragon_check()` now explains a CPU-only result on a machine with an NVIDIA
  GPU: no driver, a driver too old for the installed torch, or a CPU-only
  torch build, each with the one-line fix.
* README gains a Requirements section covering the driver requirement, disk
  space, and that the CUDA Toolkit is not needed.
* New `dragon_bundle()`, `dragon_remote()`, and `dragon_import()` take a run to
  a cloud GPU (Google Colab, Kaggle, Lightning AI, or RunPod) and bring the
  trained adapter back, for machines without a GPU. `dragon_remote_providers()`
  lists the providers. The app gains the same path in its Train and Monitor
  panels, and `dragon_check()` points to it when it finds no GPU.

# dragonfarm 0.1.0

First release.

* `dragon_dataset()`, `dragon_map()`, and `dragon_split()` turn a table into
  chat-format training data with glue templates for combining columns.
* `dragon_train()` runs LoRA fine-tuning of any Hugging Face causal language
  model in a background Python process. Runs live on disk and survive the R
  session; `dragon_run()` reopens them.
* `dragon_status()`, `dragon_progress()`, `dragon_logs()`, `dragon_wait()`,
  `dragon_cancel()`, and `dragon_resume()` manage a run.
* `dragon_evaluate()`, `dragon_generate()`, and `dragon_merge()` cover
  held-out evaluation, generation from the adapter or the base model, and
  merging into a standalone model. `dragon_export_gguf()` wraps the llama.cpp
  converter when one is available.
* `dragon_app()` launches a Shiny app with drag-and-drop dataset upload,
  drag-and-drop column mapping, a live loss curve, and a before-and-after
  comparison panel. `dragon_code()` returns the R script for any run.
* Python dependencies are declared with `reticulate::py_require()` and built
  automatically. On Windows with an NVIDIA GPU the CUDA build of torch is
  selected on first use.
