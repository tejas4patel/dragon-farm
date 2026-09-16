# Changelog

## dragonfarm (development version)

- Synthetic data closes the loop.
  [`dragon_synthesize()`](https://dragonfarm.dev/reference/dragon_synthesize.md)
  has a teacher model answer your prompts to make fine-tuning data;
  [`dragon_synthesize_pairs()`](https://dragonfarm.dev/reference/dragon_synthesize_pairs.md)
  samples a run’s own replies, has a judge score them, and keeps the
  best and worst as preference pairs (or pairs a teacher’s reply against
  the student’s).
  [`dragon_prompts()`](https://dragonfarm.dev/reference/dragon_prompts.md)
  pulls prompts from a run’s data files.
  [`dragon_llm_anthropic()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md)
  and
  [`dragon_llm_ellmer()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md)
  turn the Claude API or any ellmer chat into a teacher; the judge
  variants are now wrappers over them. The app’s Try it panel gains an
  Improve card that builds pairs from the selected run and loads them
  for the next stage.

- Evaluation that can drive decisions.
  [`dragon_evaluate()`](https://dragonfarm.dev/reference/dragon_evaluate.md)
  gains `metrics`: deterministic task checks (exact match, token F1,
  JSON validity, numeric answers, length, custom functions) over every
  held-out row.
  [`dragon_judge()`](https://dragonfarm.dev/reference/dragon_judge.md)
  scores a run’s replies with a language model or compares them pairwise
  with the model it started from, with position swapping so a biased
  judge produces ties rather than wins;
  [`dragon_judge_anthropic()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md)
  talks to the Claude API directly and
  [`dragon_judge_ellmer()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md)
  wraps any ellmer chat, and any local model can judge too.
  [`dragon_compare()`](https://dragonfarm.dev/reference/dragon_compare.md)
  puts every run’s measurements side by side. The app gains task metrics
  and a comparison table in Monitor and a Judge card in Try it.

- Post-training stages.
  [`dragon_map_pairs()`](https://dragonfarm.dev/reference/dragon_map_pairs.md)
  maps prompt, chosen, and rejected columns, and
  [`dragon_prefer()`](https://dragonfarm.dev/reference/dragon_prefer.md)
  runs preference optimization on them with DPO or ORPO. Any function
  that takes a `model` also accepts a finished run: its adapters are
  folded into the weights before the new stage adds its own, so
  fine-tune then prefer chains naturally, locally or through the cloud
  bundle. Runs record their `stage`,
  [`dragon_evaluate()`](https://dragonfarm.dev/reference/dragon_evaluate.md)
  reports preference accuracy and reward margin, and the app’s Map and
  Train panels gain a preference-pairs mode and a “Start from” run
  picker.

- Driver download link updated to NVIDIA’s canonical URL, which CRAN’s
  URL check had flagged as a redirect.

## dragonfarm 0.1.1

- [`dragon_check()`](https://dragonfarm.dev/reference/dragon_check.md)
  now explains a CPU-only result on a machine with an NVIDIA GPU: no
  driver, a driver too old for the installed torch, or a CPU-only torch
  build, each with the one-line fix.
- README gains a Requirements section covering the driver requirement,
  disk space, and that the CUDA Toolkit is not needed.
- New
  [`dragon_bundle()`](https://dragonfarm.dev/reference/dragon_bundle.md),
  [`dragon_remote()`](https://dragonfarm.dev/reference/dragon_remote.md),
  and
  [`dragon_import()`](https://dragonfarm.dev/reference/dragon_import.md)
  take a run to a cloud GPU (Google Colab, Kaggle, Lightning AI, or
  RunPod) and bring the trained adapter back, for machines without a
  GPU.
  [`dragon_remote_providers()`](https://dragonfarm.dev/reference/dragon_remote_providers.md)
  lists the providers. The app gains the same path in its Train and
  Monitor panels, and
  [`dragon_check()`](https://dragonfarm.dev/reference/dragon_check.md)
  points to it when it finds no GPU.

## dragonfarm 0.1.0

First release.

- [`dragon_dataset()`](https://dragonfarm.dev/reference/dragon_dataset.md),
  [`dragon_map()`](https://dragonfarm.dev/reference/dragon_map.md), and
  [`dragon_split()`](https://dragonfarm.dev/reference/dragon_split.md)
  turn a table into chat-format training data with glue templates for
  combining columns.
- [`dragon_train()`](https://dragonfarm.dev/reference/dragon_train.md)
  runs LoRA fine-tuning of any Hugging Face causal language model in a
  background Python process. Runs live on disk and survive the R
  session;
  [`dragon_run()`](https://dragonfarm.dev/reference/dragon_run.md)
  reopens them.
- [`dragon_status()`](https://dragonfarm.dev/reference/dragon_status.md),
  [`dragon_progress()`](https://dragonfarm.dev/reference/dragon_status.md),
  [`dragon_logs()`](https://dragonfarm.dev/reference/dragon_status.md),
  [`dragon_wait()`](https://dragonfarm.dev/reference/dragon_wait.md),
  [`dragon_cancel()`](https://dragonfarm.dev/reference/dragon_cancel.md),
  and
  [`dragon_resume()`](https://dragonfarm.dev/reference/dragon_resume.md)
  manage a run.
- [`dragon_evaluate()`](https://dragonfarm.dev/reference/dragon_evaluate.md),
  [`dragon_generate()`](https://dragonfarm.dev/reference/dragon_generate.md),
  and
  [`dragon_merge()`](https://dragonfarm.dev/reference/dragon_merge.md)
  cover held-out evaluation, generation from the adapter or the base
  model, and merging into a standalone model.
  [`dragon_export_gguf()`](https://dragonfarm.dev/reference/dragon_export_gguf.md)
  wraps the llama.cpp converter when one is available.
- [`dragon_app()`](https://dragonfarm.dev/reference/dragon_app.md)
  launches a Shiny app with drag-and-drop dataset upload, drag-and-drop
  column mapping, a live loss curve, and a before-and-after comparison
  panel.
  [`dragon_code()`](https://dragonfarm.dev/reference/dragon_code.md)
  returns the R script for any run.
- Python dependencies are declared with
  [`reticulate::py_require()`](https://rstudio.github.io/reticulate/reference/py_require.html)
  and built automatically. On Windows with an NVIDIA GPU the CUDA build
  of torch is selected on first use.
