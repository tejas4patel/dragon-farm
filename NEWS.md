# dragonfarm (development version)

* The Python side (`inst/python`) is now also its own installable package:
  `pip install ./inst/python` (or a built wheel) gives a `dragonfarm`
  command (`check`, `train`, `generate`, `pack`) and a `dragonfarm.api`
  module (`Run`, `runs()`) for reading a run directory from plain Python,
  with no R involved. A run started from R can be inspected or continued
  from Python and back, since both read and write the same files. Not yet
  published to PyPI.

* Runs can be archived, restored, and deleted. `dragon_archive_run()` moves
  a run's directory under `archived/` (every file kept; it just drops out
  of `dragon_runs()` and the app); `dragon_unarchive_run()` brings it back;
  `dragon_delete_run()` removes it for good. Both refuse a run that is
  queued or running, or one that another run continues from, unless
  `force = TRUE`. The Monitor panel gets Archive and Delete buttons (Delete
  asks for confirmation first), a "Show archived" toggle, and Restore.

* Chat gets context limits, a second backend to compare with, and transcript
  round-tripping in the app. `dragon_chat(context_window=)` tracks an
  approximate token budget and automatically drops the oldest turns to stay
  under it; `$context_usage()` reports tokens used, the window, and how many
  turns were dropped. The Chat tab shows a warning banner near the limit, a
  "Compare with a second backend" toggle sends the same message to a second
  backend or run side by side (feedback stays scoped to the primary
  conversation), and Load transcript / Export as training example round out
  Save transcript.
* Fixed a bug in the Chat tab (introduced while building the above) where
  Shiny's default "suspend when hidden" behaviour left the conversation
  panes permanently blank the first time the tab was opened, because they
  sit behind a `renderUI()` rather than being part of the tab's static
  markup; the affected outputs now opt out of that suspension.

* `dragon_synthesize()` gets a quality pass and a judge filter. It now
  drops replies that are too short or too long, look garbled or
  wrong-script, repeat an earlier prompt, or repeat (or nearly repeat) an
  earlier response, before writing the dataset. Passing a `judge` scores
  every surviving reply and keeps only the ones at or above `min_score`,
  for teacher distillation with a quality gate -- pass a run's own prompts
  (`dragon_prompts(run, "train")`) to distill and filter in one call.

* The app no longer freezes on long actions. Evaluate, Run judge, Build
  preference pairs, and Merge run as one-step background pipelines; the
  panel shows progress, the result appears when it lands, and the Pipeline
  panel lists them.
* `dragon_pipeline_cancel()` and a Cancel button on running pipelines. A
  training step in flight stops after saving a checkpoint; other steps
  finish first. Records now carry the runner's pid, so a pipeline whose
  process died reads as failed instead of running forever.
* `dragon_step_merge()`: a pipeline step that writes the latest run as a
  standalone model.
* `dragon_publish()`: push a run's merged model or adapter to a repo on the
  Hugging Face Hub, creating it if needed. `dragon_step_publish()` for
  pipelines, and a Publish card in the app's Try it panel.

* Human feedback becomes data. In `dragon_chat()` and the app's Chat panel,
  replies can be rated up or down, edited, or regenerated; every verdict is
  saved under `feedback/`. `dragon_feedback()` turns them into a
  conversations dataset of liked and edited replies and a preference-pairs
  dataset where the same prompt drew a liked and a disliked reply.
* `dragon_conversations()`: whole multi-turn conversations as training
  data, from a list, a JSONL file, or a data frame. They train wherever
  prompt and response rows do.
* Two new vignettes: the post-training loop, and reinforcement learning
  with verifiable rewards.

* Inference backends. `dragon_generate()` and everything built on it now
  route through a `backend`: `dragon_backend_local()` is a Python worker
  that keeps the last two models loaded, so repeated calls no longer reload
  the model; `dragon_backend_server()` talks to any OpenAI-compatible chat
  endpoint (vLLM, llama.cpp, LM Studio, hosted services), and
  `dragon_backend_ollama()` to Ollama. `dragon_serve_ollama()` merges a run
  and registers it with Ollama in one call. `dragon_worker_stop()` frees the
  worker's memory. Set a session default with `options(dragonfarm.backend)`.
* `dragon_chat()`: a conversation object with memory, streaming through
  `on_token` where the backend supports it, save and load of transcripts,
  and export of a conversation as a training example. The app gains a Chat
  panel with a backend selector and a system prompt.

# dragonfarm 0.2.0

* Pipelines. `dragon_pipeline()` chains stages built from `dragon_step_*()`
  constructors (train, synthesize pairs, prefer, reinforce, judge,
  evaluate), threading each stage's run into the next and writing a record
  after every step. `background = TRUE` runs it in a separate R process;
  `dragon_pipeline_status()` follows it. `dragon_compare()` accepts a
  pipeline. The app gains a Pipeline panel that launches the standard
  recipe and shows every run's lineage.

* Reinforcement learning. `dragon_map_prompts()` maps prompts with an
  optional reference answer, `dragon_reward()` defines verifiable rewards
  (exact, contains, numeric, regex, JSON, length, keyword, or a custom
  Python function), and `dragon_reinforce()` runs GRPO: the model samples a
  group of answers per prompt, the rewards score them, and it learns from
  the ones that beat their group's average, with a KL penalty towards the
  model it started from. Implemented in the package's own trainer, so no
  new dependency. Evaluation reports mean held-out reward per reward; the
  app's Map and Train panels gain an RL mode with a reward builder.

* Synthetic data closes the loop. `dragon_synthesize()` has a teacher model
  answer your prompts to make fine-tuning data; `dragon_synthesize_pairs()`
  samples a run's own replies, has a judge score them, and keeps the best
  and worst as preference pairs (or pairs a teacher's reply against the
  student's). `dragon_prompts()` pulls prompts from a run's data files.
  `dragon_llm_anthropic()` and `dragon_llm_ellmer()` turn the Claude API or
  any ellmer chat into a teacher; the judge variants are now wrappers over
  them. The app's Try it panel gains an Improve card that builds pairs from
  the selected run and loads them for the next stage.

* Evaluation that can drive decisions. `dragon_evaluate()` gains `metrics`:
  deterministic task checks (exact match, token F1, JSON validity, numeric
  answers, length, custom functions) over every held-out row.
  `dragon_judge()` scores a run's replies with a language model or compares
  them pairwise with the model it started from, with position swapping so a
  biased judge produces ties rather than wins; `dragon_judge_anthropic()`
  talks to the Claude API directly and `dragon_judge_ellmer()` wraps any
  ellmer chat, and any local model can judge too. `dragon_compare()` puts
  every run's measurements side by side. The app gains task metrics and a
  comparison table in Monitor and a Judge card in Try it.

* Post-training stages. `dragon_map_pairs()` maps prompt, chosen, and
  rejected columns, and `dragon_prefer()` runs preference optimization on
  them with DPO or ORPO. Any function that takes a `model` also accepts a
  finished run: its adapters are folded into the weights before the new
  stage adds its own, so fine-tune then prefer chains naturally, locally or
  through the cloud bundle. Runs record their `stage`, `dragon_evaluate()`
  reports preference accuracy and reward margin, and the app's Map and Train
  panels gain a preference-pairs mode and a "Start from" run picker.

* Driver download link updated to NVIDIA's canonical URL, which CRAN's URL
  check had flagged as a redirect.

# dragonfarm 0.1.1

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
