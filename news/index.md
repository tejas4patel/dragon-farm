# Changelog

## dragonfarm (development version)

- The app no longer freezes on long actions. Evaluate, Run judge, Build
  preference pairs, and Merge run as one-step background pipelines; the
  panel shows progress, the result appears when it lands, and the
  Pipeline panel lists them.

- [`dragon_pipeline_cancel()`](https://dragonfarm.dev/reference/dragon_pipeline_cancel.md)
  and a Cancel button on running pipelines. A training step in flight
  stops after saving a checkpoint; other steps finish first. Records now
  carry the runner’s pid, so a pipeline whose process died reads as
  failed instead of running forever.

- [`dragon_step_merge()`](https://dragonfarm.dev/reference/dragon_step.md):
  a pipeline step that writes the latest run as a standalone model.

- Human feedback becomes data. In
  [`dragon_chat()`](https://dragonfarm.dev/reference/dragon_chat.md) and
  the app’s Chat panel, replies can be rated up or down, edited, or
  regenerated; every verdict is saved under `feedback/`.
  [`dragon_feedback()`](https://dragonfarm.dev/reference/dragon_feedback.md)
  turns them into a conversations dataset of liked and edited replies
  and a preference-pairs dataset where the same prompt drew a liked and
  a disliked reply.

- [`dragon_conversations()`](https://dragonfarm.dev/reference/dragon_conversations.md):
  whole multi-turn conversations as training data, from a list, a JSONL
  file, or a data frame. They train wherever prompt and response rows
  do.

- Two new vignettes: the post-training loop, and reinforcement learning
  with verifiable rewards.

- Inference backends.
  [`dragon_generate()`](https://dragonfarm.dev/reference/dragon_generate.md)
  and everything built on it now route through a `backend`:
  [`dragon_backend_local()`](https://dragonfarm.dev/reference/dragon_backend.md)
  is a Python worker that keeps the last two models loaded, so repeated
  calls no longer reload the model;
  [`dragon_backend_server()`](https://dragonfarm.dev/reference/dragon_backend.md)
  talks to any OpenAI-compatible chat endpoint (vLLM, llama.cpp, LM
  Studio, hosted services), and
  [`dragon_backend_ollama()`](https://dragonfarm.dev/reference/dragon_backend.md)
  to Ollama.
  [`dragon_serve_ollama()`](https://dragonfarm.dev/reference/dragon_serve_ollama.md)
  merges a run and registers it with Ollama in one call.
  [`dragon_worker_stop()`](https://dragonfarm.dev/reference/dragon_worker_stop.md)
  frees the worker’s memory. Set a session default with
  `options(dragonfarm.backend)`.

- [`dragon_chat()`](https://dragonfarm.dev/reference/dragon_chat.md): a
  conversation object with memory, streaming through `on_token` where
  the backend supports it, save and load of transcripts, and export of a
  conversation as a training example. The app gains a Chat panel with a
  backend selector and a system prompt.

## dragonfarm 0.2.0

- Pipelines.
  [`dragon_pipeline()`](https://dragonfarm.dev/reference/dragon_pipeline.md)
  chains stages built from `dragon_step_*()` constructors (train,
  synthesize pairs, prefer, reinforce, judge, evaluate), threading each
  stage’s run into the next and writing a record after every step.
  `background = TRUE` runs it in a separate R process;
  [`dragon_pipeline_status()`](https://dragonfarm.dev/reference/dragon_pipeline_status.md)
  follows it.
  [`dragon_compare()`](https://dragonfarm.dev/reference/dragon_compare.md)
  accepts a pipeline. The app gains a Pipeline panel that launches the
  standard recipe and shows every run’s lineage.

- Reinforcement learning.
  [`dragon_map_prompts()`](https://dragonfarm.dev/reference/dragon_map_prompts.md)
  maps prompts with an optional reference answer,
  [`dragon_reward()`](https://dragonfarm.dev/reference/dragon_reward.md)
  defines verifiable rewards (exact, contains, numeric, regex, JSON,
  length, keyword, or a custom Python function), and
  [`dragon_reinforce()`](https://dragonfarm.dev/reference/dragon_reinforce.md)
  runs GRPO: the model samples a group of answers per prompt, the
  rewards score them, and it learns from the ones that beat their
  group’s average, with a KL penalty towards the model it started from.
  Implemented in the package’s own trainer, so no new dependency.
  Evaluation reports mean held-out reward per reward; the app’s Map and
  Train panels gain an RL mode with a reward builder.

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
