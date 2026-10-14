# dragonfarm (development version)

* `dragon_questions()` no longer dies when one batch runs out of GPU memory:
  the batch is retried one chunk at a time, a chunk that does not fit even
  alone is skipped and listed in the set's metadata (`skipped_oom`), and the
  passage shown to the generator is capped at 450 words so a long code block
  cannot blow the budget. Seen with the 7B generator on an 8 GB card, 236
  chunks into R's own manuals.

* Reading PDFs is cleaner, measured on R's own manuals: running page headers
  and footers, page numbers, and contents lines are dropped; a sentence that
  breaks across a page is rejoined; code prompts, lead-in lines before an
  example, and sentence fragments are no longer taken for section headings
  (R-intro went from 97 section names, one of them 1,489 characters long, to
  79 real ones). A manual or FAQ with numbered sections ("2.1 What is R?") is
  no longer mistaken for a changelog and down-weighted. HTML headings lose
  the anchor glyph some generators append (the pilcrow after every R FAQ
  heading, for example).

* `dragon_check()` now reports how much GPU memory other programs already
  hold and lists dragonfarm Python processes started by other R sessions (an
  app left open elsewhere, a worker that outlived its console). Training
  warns when such a process is running, and `dragon_worker_stop(all = TRUE)`
  stops them. An orphaned worker has twice made a run look out of memory when
  it was not.

* `dragon_example_documents()`: three short policy documents for the
  fictional smart-home company behind the example tickets, so the document
  route can be tried before bringing your own files. The Documents tab has a
  "Load the example policies" button.

* New: documents to training data. `dragon_questions()` has a model write
  questions and answers from each chunk of a document set (the local model
  recommended for the machine, in the background; or a teacher such as
  `dragon_llm_anthropic()`), runs simple deterministic filters, and returns
  every pair with `keep` and a `reason`, because the measured yield of usable
  pairs is 20 to 60 percent depending on the model and a review step is not
  optional. `dragon_questions_save()` records your decisions;
  `dragon_questions_dataset()` builds the training set with retrieved
  excerpts placed in front of each question, the setup that beat a plain
  fine-tune in the prototypes. The Documents tab gains a **Teach** card:
  generate, watch the yield grow, review pairs grouped by chunk, tick and
  untick, then Continue to Model, which skips Data and Map.

* The app now starts with documents. A new **Documents** tab is tab 1: drop
  files or add web pages, press Read and index, ask questions and see the
  sources, then continue in Chat with the same set. The default route runs
  Documents, Model, Train, Monitor, Try it, Chat, Pipeline; the table route
  (Data and Map first, today's app) is one link away ("Have a table of
  prompts and replies instead?") or `dragon_app(route = "table")`. The Chat
  and Try it pickers preselect the set open on the Documents tab.

* New: ask questions of your documents, no training needed. `dragon_index()`
  embeds a document set with a small encoder (`BAAI/bge-small-en-v1.5` by
  default, kept warm in the inference worker), `dragon_retrieve()` returns
  the most relevant chunks, and `dragon_ask()` puts them in front of a model
  as numbered excerpts and returns the answer with its sources, marking which
  were cited. The model defaults to the one `dragon_check()` recommends for
  the GPU and can be any run, model id, or server backend. `dragon_chat()`
  gains `documents` and `k`: each turn is answered from retrieved excerpts
  while the transcript keeps the plain questions, and `$sources()` shows the
  excerpts behind the last reply. `dragon_documents()` now indexes right away
  (`index = FALSE` to postpone). Changelog-like sources are down-weighted at
  retrieval time.

* 4-bit loading for generation, on Windows as well as Linux.
  `dragon_backend_local()` gains `load_in_4bit`: `"auto"` (the default)
  quantizes a model to NF4 through bitsandbytes only when its full weights
  would not fit the GPU, so `dragon_generate("Qwen/Qwen2.5-7B-Instruct", ...)`
  now works on an 8 GB card (about 5.5 GB of weights, 7.2 GB peak) while a 3B
  still loads in full precision. `dragon_check()` reports whether 4-bit
  loading is available and which model it would reach for on this machine,
  by GPU memory: a 1.5B under 6 GB, a 3B at 6 to 8 GB, a 7B in 4-bit at 8 GB
  and up. `bitsandbytes` is added to the Python requirements on Linux and
  Windows. `dragon_hardware(load_in_4bit = TRUE)` (QLoRA training) is no
  longer refused on Windows. Measured on an 8 GB RTX 4060: three epochs of
  Qwen2.5-7B-Instruct on the 190 example tickets, batch 1 x 8, 512 tokens,
  gradient checkpointing on, took 22 minutes with the weights already cached
  (a cold first load adds about five) and peaked at 7.9 GB, so an 8 GB card
  is the floor and longer sequences will not fit. The result reproduced the
  example policies on held-out tickets where the 0.5B had drifted (held-out
  loss 0.02 against 0.24); one epoch was not enough and produced fluent
  replies that blended policies.

* New: `dragon_documents()` reads PDF, HTML, Markdown, text, Word, spreadsheet
  files, directories of them, and web pages into a *document set*: chunks of
  about 170 words that never cross a heading, each keeping its file and
  section, stored under `runs_dir/documents/<name>/`. Reading again re-reads
  only files whose contents changed. Changelog-like files are flagged and
  down-weighted; quoted material and code blocks are marked on each chunk.
  `dragon_chunks()`, `dragon_documents_load()`, and `dragon_documents_list()`
  go with it. This is the first piece of the document route (drop in
  documents, ask, then fine-tune); retrieval and answering follow. The Python
  environment gains `pypdf`, `python-docx`, and `openpyxl`.

* A run can no longer be marked failed by an out-of-memory error in the
  evaluation that follows training. Scoring the held-out rows materialized
  the full `batch x tokens x vocabulary` logits tensor; with a 150k-token
  vocabulary, a long `max_seq_len`, and the training batch size, that tensor
  alone was several gigabytes, and on an 8 GB GPU that was also holding a
  loaded inference worker from the app, the run failed *after* the adapter
  had been saved. Held-out loss is now computed in chunks of 256 positions
  through the output layer, both in the Trainer's end-of-epoch evaluation
  and in the end-of-run one, so the full tensor is never built; the trainer's
  optimizer state is released before the final evaluation; evaluation falls
  back to one row at a time if a batch still does not fit; and if even that
  fails the run succeeds with an `eval_warning` in `status.json` (shown in
  the Monitor panel and by `print()`) instead of failing. `dragon_train_args()`
  gains `eval_batch_size` (default 1; it was silently the training batch size
  before). Measured on `Qwen2.5-0.5B-Instruct` with a batch of 4 x 1536
  tokens: peak evaluation memory fell from 7.9 GB to 2.4 GB, with the same
  loss to the last decimal.

* `dragon_example_data()` no longer contains duplicate tickets. The 200 example
  support tickets used to be drawn with replacement from 315 possible ones, so
  about a quarter were repeats and a "held-out" row often had an identical twin
  in the training rows, which made held-out loss and perplexity look nearly
  perfect. The tickets are now 200 distinct ones, and each issue is answered in
  one of three wordings instead of a single fixed reply, so held-out numbers
  are no longer inflated by verbatim repeats. The tickets are still synthetic
  and built from templates, so treat the example as a smoke test, not a
  benchmark.

* Fixed the Shiny app clipping its own controls. The navbar page was
  "fillable", so every card on a panel shared a single screenful of height:
  on the Map step the drag-and-drop slots were cut off to a thin strip, and on
  the Try it panel the Generate button and the Judge, Improve, Export, and
  Publish cards were squeezed into short scroll boxes. Panels now take their
  natural height and the page scrolls. The Monitor loss plot is given a fixed
  height so it does not stretch to match the taller Runs card beside it.

# dragonfarm 0.3.4

* Fixed a test that failed on macOS (CRAN's M1mac additional check) though it
  passed everywhere else. It compared `dragon_runs_dir()`'s default, a
  directory that does not exist yet, against `tempdir()` after
  `normalizePath()`; on macOS that resolves `/var` to `/private/var` for the
  existing `tempdir()` but leaves the nonexistent path unresolved, so the
  prefix check failed. The test now compares the existing parent directory.
  No change to package code or behaviour.

# dragonfarm 0.3.3

* Fixed the Shiny app's Try it, Chat, Train, and Pipeline panels sometimes
  keeping a stale runs list until the page was reloaded -- most visibly, a
  run that had just finished training would not appear as selectable in Try
  it. Their `reactivePoll()`s watched only each run's own `status.json`
  mtime, which misses a change when the file that actually matters (the
  adapter, or a run's directory being renamed by archive/restore) is written
  or moved without `status.json` itself changing again. All of the app's
  run-list pollers now share `runs_change_signature()`, which changes
  whenever any file anywhere under the runs directory is added, edited, or
  moved.

# dragonfarm 0.3.2

* The 0.3.1 fix for the torchao `ImportError` on cloud GPUs (pinning
  `torchao>=0.16.0` in requirements) turned out not to be reliably honored on
  Colab's and Kaggle's preinstalled environment (pip reported success but the
  old 0.10.0 build was still what got imported). The requirements pin is
  reverted, and the shared remote notebook (`inst/remote/dragonfarm_remote.ipynb`,
  used by `dragon_remote()` for Colab, Kaggle, Lightning AI, and RunPod) now
  explicitly uninstalls torchao after installing the trainer's requirements.
  dragonfarm never imports torchao itself, and peft's LoRA dispatch skips its
  torchao check cleanly when the package is entirely absent rather than
  present at an old version, so removing it sidesteps the problem instead of
  depending on pip to upgrade it in place.

# dragonfarm 0.3.1

* Fixed cloud training (`dragon_remote()` on Colab, Kaggle, Lightning AI, and
  RunPod) failing with `ImportError: Found an incompatible version of
  torchao`. dragonfarm never uses torchao, but recent `peft` versions probe
  it while dispatching LoRA and raise instead of skipping when an older
  version is already installed, which Colab and Kaggle's base images ship by
  default. `dragon_python_requirements()` now pins `torchao>=0.16.0` so the
  bundled `requirements.txt` installs a compatible version.

# dragonfarm 0.3.0

CRAN maintainers reviewed 0.1.1 and asked for several changes, folded into
this release along with everything added since 0.2.0:

* **Where runs are stored by default has changed.** `dragon_runs_dir()` used
  to default to `dragonfarm_runs` under the working directory; a package
  must not write there without being asked. It now defaults to
  `dragonfarm_runs` under a session temp directory, so a fresh R session
  never writes to your project or home folder on its own, and that folder
  disappears when the session ends. For runs you want to keep, set
  `options(dragonfarm.runs_dir = "path/to/dragonfarm_runs")` or the
  `DRAGONFARM_RUNS_DIR` environment variable once, or pass `runs_dir=` to
  the function you're calling. See `?dragon_runs_dir` and the README.
* Fixed three places (`dragon_judge()`, `dragon_split()`,
  `dragon_synthesize()`/`dragon_prompts()`) that saved and restored
  `.Random.seed` by hand for a seeded sample; they now use
  `withr::with_seed()`, which does the same thing without dragonfarm's own
  code touching `.GlobalEnv`. `withr` moved from Suggests to Imports.
  `dragon_resume()`'s log line now goes through a small file-append helper
  rather than `cat()`.
* Examples that need Python, a GPU, or a model download now use
  `if (interactive())` instead of `\dontrun{}`, so `R CMD check` at least
  parses them; they still don't run during checks or on CRAN's servers.
* Package and software names in the `Title` and `Description` fields are
  now quoted and cased correctly (`'Python'`, `'shiny'`), and quotes were
  removed from `LoRA`, which is a technique name, not a package.
* Added `testthat`-based tests for the three app modules (Data, Model, Try
  it) that had none, covering their server logic without needing a real
  Shiny session, Python, or a GPU.

## Everything else added since 0.2.0

* `dragon_reward("command", command = ...)`: a reward for `dragon_reinforce()`
  that runs a command (a test suite, a linter) against the completion and
  scores by its exit code or a number in its stdout. Runs the command
  directly, never through a shell, so the completion's own text cannot
  inject anything into the command line.

* The Chat tab streams replies token by token, for the local worker and for
  server backends alike, instead of showing the whole reply only once
  generation finishes. Compare mode still shows each side's full reply once
  it lands.

* Starting a training run now stops the local inference worker first, if
  one is loaded from an earlier Try it or Chat call. Two heavy Python/CUDA
  processes starting at the same moment has occasionally crashed a fresh
  trainer on Windows; freeing the worker's GPU memory first is the most
  likely trigger and costs nothing, since the worker restarts automatically
  on the next generation call.

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
