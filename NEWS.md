# dragonfarm 0.4.0

The headline of this release is a document route: drop in PDFs, Word files,
web pages, or spreadsheets, ask questions with cited sources, have a model
write training questions from them, review those, and fine-tune. The app now
opens on it, has a new look with a dark mode, and can train a 7B model in
4-bit on an 8 GB GPU. Everything below was measured on an 8 GB laptop GPU
(RTX 4060) and on real documents: R's own manuals, a 76-page annual report as
PDF and as Word, live web pages, and a spreadsheet.

## Documents

* New: `dragon_documents()` reads PDF, HTML, Markdown, text, Word,
  spreadsheet files, directories of them, and web pages into a *document
  set*: chunks of about 170 words that never cross a heading, each keeping
  its file, section, and (for PDFs) page, stored under
  `runs_dir/documents/<name>/`. Reading again re-reads only files whose
  contents changed, and a set built by an older version of the readers is
  re-read rather than reused. `dragon_chunks()` (with a `page` column),
  `dragon_documents_load()`, and `dragon_documents_list()` go with it. The
  Python environment gains `pypdf`, `python-docx`, and `openpyxl`.
* `dragon_example_documents()`: three short policy documents for the
  fictional company behind the example tickets, so the route can be tried
  before bringing your own files.
* PDFs. Pages whose text comes out of the standard extractor as two-letter
  fragments (`Co st co Wh ol es al e`, common in annual reports) are re-read
  in a layout-aware mode: a 76-page annual report went from 726 unreadable
  chunks to 273 readable ones under real section names. Running headers,
  page numbers, contents entries with dot leaders, and dot leaders inside
  table rows are dropped; a sentence broken across pages is rejoined; code,
  lead-in lines, rows of numbers, and single words are no longer taken for
  headings (R-intro went from 97 section names, one 1,489 characters long, to
  79 real ones); apostrophes a font did not map are restored. A PDF with no
  text layer (a scan) is reported by name with advice to run OCR first,
  instead of silently adding nothing.
* Year columns. In a financial table the years are printed once, above the
  figures; flattened into text, nothing said which figure was which year, and
  answers came from the wrong column. Rows under a year header that end in
  one figure per year now carry the years: "Net cash used in investing
  activities (2024: (4,409); 2023: (4,972); 2022: (3,915))". On ten questions
  about an annual report that need a specific year's figure, correct answers
  went from 5 to 9, and confident wrong-column answers from 2 to none. Word
  tables get the same treatment from a header row of dates, and their merged
  cells are no longer repeated once per column they span ("249,625 |
  249,625"); the Word copy of the report went from 8 to 10 of 10.
* Units. A note such as "(dollars in millions, except per share data)" is
  carried into later chunks that show money without a unit word, so answers
  from financial tables say "$4,409 million" rather than "$4,409".
* Word. Unit notes styled as headings set the unit instead of becoming a
  section; short paragraphs set entirely in bold or italic become headings
  when prose follows them (the sub-headings of a 10-K are italic), while table
  column labels, which look the same, stay text. The Word annual report went
  from one 38-chunk "Note 1" to 123 real sections.
* Web pages. Blocks made mostly of links and regions marked as navigation,
  banner, footer, or search are dropped, so a page without a `<nav>` tag no
  longer leaks its menu into the first chunk. Heading anchor glyphs (the
  pilcrow after every R FAQ heading) are removed.
* Spreadsheets. Each row becomes "column: value" pairs; a two-column
  label-and-value sheet is read as such rather than as a header plus data; a
  first row of numbers is not taken for column names; and each sheet starts
  its own chunk.
* A manual or FAQ with numbered sections ("2.1 What is R?") is no longer
  mistaken for a changelog; changelog-like files are still flagged and
  down-weighted, and quoted material and code blocks are marked on each chunk.

## Asking documents

* New: `dragon_index()` embeds a document set with a small encoder
  (`BAAI/bge-small-en-v1.5`, kept warm in the inference worker),
  `dragon_retrieve()` returns the most relevant chunks, and `dragon_ask()`
  puts them in front of a model as numbered excerpts and returns the answer
  with its sources, marking which were cited: "report.pdf, p. 68 › Item 14".
  The model defaults to the one `dragon_check()` recommends for the GPU and
  can be any run, model id, or server backend. `dragon_chat()` gains
  `documents` and `k`; `$sources()` shows the excerpts behind the last reply.
* Retrieval is hybrid by default: the embedding ranking is combined with a
  keyword (`BM25`) ranking over each chunk's section title and text,
  counting only chunks that share a word with the question, and the
  embedding's own best match always stays among the excerpts. Exact terms
  and figures that a small embedding model ranks a few places too low still
  reach the answer. The share of questions whose source chunk was among the
  four excerpts, embedding alone against hybrid: R's manuals 90.7 to 94.5
  percent (616 questions), the package documentation 88 to 100, a
  spreadsheet 83 to 100; on an annual report the right chunk is ranked first
  for 75 to 83 percent of questions, up from 58 to 67.
  `dragon_retrieve(method = "dense")` keeps the embedding ranking alone, and
  `scripts/retrieval_eval.py` measures both on any indexed sets.
* On the annual report the default 7B in 4-bit answers 20 to 23 of 23
  factual questions with known answers (Word copy 23, PDF 20 to 21),
  including ten that need a specific year's figure from a table. The PDF
  misses a total printed inside a map graphic, and the model says so rather
  than guessing. Six excerpts instead of four did not help.

## From documents to training data

* New: `dragon_questions()` has a model write questions and answers from each
  chunk (the local model recommended for the machine, in the background, or
  a teacher such as `dragon_llm_anthropic()`), runs deterministic filters,
  and returns every pair with `keep` and a `reason`. With the default 7B,
  78 to 87 percent of pairs passed on real documents; a small generator does
  far worse, so review is part of the workflow. A batch that runs out of GPU
  memory is retried one chunk at a time, and long passages are capped.
  `dragon_questions_save()` records your decisions.
* `dragon_questions_dataset()` builds the training set with retrieved
  excerpts in front of each question, always including the chunk the pair
  was written from, and appends that excerpt's number to the answer
  (`cite = TRUE`) so a tuned model keeps citing. It warns if the document
  set was re-read after the questions were written.

## The app

* The app starts with documents. A new **Documents** tab is tab 1: drop
  files or add web pages, read and index, ask with sources, continue in Chat.
  Its **Teach** card generates questions in the background, shows the yield
  as it grows, and lets you tick and untick pairs grouped by chunk before
  Continue to Model, which skips Data and Map. The table route (Data and Map
  first) is one link away or `dragon_app(route = "table")`.
* Panels take their natural height and the page scrolls; the Map step's
  drop slots and the Try it cards are no longer clipped. A message now says
  to wait for "Upload complete" when Read and index is pressed while a large
  file is still uploading.
* A new look that matches dragonfarm.dev: a dark navbar whose tabs read as
  numbered steps, a one-line introduction on each step, the website's fonts
  and amber-to-coral accents, model presets as selectable cards with size,
  memory, and licence, a loss chart in the same colours, and a dark mode
  switch in the navbar.
* The Training step can load the model in 4-bit (QLoRA), so a 7B trains from
  the app on an 8 GB NVIDIA card. The box ticks itself, with gradient
  checkpointing, when the chosen model's full-precision weights would crowd
  the GPU (a 3B or 7B on 8 GB), sets batch size 1 with gradient
  accumulation raised to keep the effective batch, and says so when there is
  no NVIDIA GPU.

## Hardware and models

* `dragon_presets()` adds Qwen 2.5 3B and 7B, both trained in 4-bit (a 3B
  peaks at 4.3 GB on 1,536-token document prompts, a 7B at 7.9 GB), and its
  notes now say which task each size suits. A new `load_in_4bit` column says
  which presets need 4-bit to fit. On the documents route the app's Model
  step starts from the model the hardware check recommends (a 7B at 8 GB,
  a 3B at 6 GB) and warns when a model under 3B is chosen for documents.
  The measurements behind this are in a new article, "Choosing a model size".

* Training computes its loss through the output layer in chunks, so the
  scores for the whole vocabulary are never held at every position at once.
  With a 151,000-token vocabulary that tensor was about a gigabyte per row
  at 1,536 tokens. Training a 0.5B on 616 document pairs at 1,536 tokens ran
  out of memory on an 8 GB card; it now peaks at 6.2 GB and takes 8
  minutes, where turning on gradient checkpointing to make it fit took 29.
  The loss and its gradients are identical to the model's own (tested).
  It is used only for batches whose full scores would exceed 256 MB
  (`DRAGONFARM_CHUNKED_LOSS_MB`); shorter batches keep the original path,
  which kept a 7B in 4-bit on short rows at 13 seconds a step where always
  chunking took 54. `DRAGONFARM_FULL_LOSS` turns it off entirely. With it,
  a 7B in 4-bit trains on 1,536-token document prompts on an 8 GB card (616
  pairs, three epochs, 4.3 hours); the tuned 7B matched the untrained one on
  accuracy and always cited its excerpt.
* 4-bit loading for generation, on Windows as well as Linux.
  `dragon_backend_local(load_in_4bit = "auto")` quantizes a model to NF4 only
  when its full weights would not fit the GPU, so a 7B runs on an 8 GB card
  (about 5.5 GB of weights) while a 3B still loads in full precision.
  `dragon_check()` reports whether 4-bit loading is available and which model
  it would use: a 1.5B under 6 GB, a 3B at 6 to 8 GB, a 7B in 4-bit at 8 GB
  and up. QLoRA training (`dragon_hardware(load_in_4bit = TRUE)`) works on
  Windows: three epochs of Qwen2.5-7B-Instruct on the 190 example tickets
  took 22 minutes on the 8 GB card, peaked at 7.9 GB, and reproduced the
  example policies on held-out tickets where the 0.5B had drifted.
* `dragon_check()` reports GPU memory already held by other programs and
  lists dragonfarm processes started by other R sessions; training warns
  about them, and `dragon_worker_stop(all = TRUE)` stops them.
* Generating for several prompts at once runs them in batches of eight:
  eight short prompts through a 0.5B went from 17 to 37 seconds to 6.

## Fixes

* The Monitor shows "Cancel run" only while a run is queued or running, and
  "Resume from checkpoint" only after it failed or was cancelled; both used
  to show for every run, finished ones included.

* `dragon_ask()` asks once more, in the same conversation, when a model
  replies with nothing but a citation marker such as "[1]". The 3B did this
  on 6 of 65 benchmark questions; with the retry it left none empty and
  answered 28 of 32 questions about R's manuals instead of 24.

* The app no longer slows to a crawl with many runs. Seven panels each
  listed every file under the runs folder every three seconds, checkpoints
  and indexes included; with a thousand files that took about a second a
  time and kept the app busy. They now look two levels deep (7.5 times
  faster here). The Monitor also stopped resetting a run you had just
  picked back to the newest one when the run list refreshed.

* A training run that runs out of GPU memory now says so, with the usual
  fixes, including when the error arrives as `CUBLAS_STATUS_EXECUTION_FAILED`
  (a 7B in 4-bit at batch size 4 on an 8 GB card) rather than "out of memory".

* A background pipeline that was cancelled or stopped left an `Rscript*`
  file in the temporary folder on Windows, because the code was passed with
  `Rscript -e`. Pipelines now run from a script file next to their record.

* After the local model stopped answering in time (or a request was
  interrupted), its late reply was taken as the answer to the next question,
  so every later answer was one question behind. Requests to the inference
  worker now carry an id and replies to another request are skipped; a worker
  that times out is stopped and the next call starts a fresh one.

* `dragon_questions()` no longer errors at the very end of a long run. The
  generator reports every chunk done a moment before it writes "done";
  the progress bar closed itself at 100 percent and the next update failed
  with "Cannot find progress bar", after all the questions had been
  written.
* A run is no longer marked failed by an out-of-memory error in the
  evaluation after training. Held-out loss is computed in chunks through the
  output layer, optimizer state is released first, and a run whose
  evaluation still cannot fit succeeds with an `eval_warning`. Peak
  evaluation memory at 4 x 1536 tokens fell from 7.9 GB to 2.4 GB with the
  same loss. `dragon_train_args()` gains `eval_batch_size` (default 1).
* Large requests to the inference worker no longer hang: replies longer than
  processx's line buffer are reassembled, and big requests are written in a
  loop.
* `dragon_example_data()` no longer contains duplicate tickets, so held-out
  numbers are not inflated by verbatim repeats. The tickets are synthetic;
  treat them as a smoke test, not a benchmark.

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
  `torchao>=0.16.0` in requirements) turned out not to be reliably honoured on
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
