# dragon-farm backlog

Updated 2026-09-16. Items carry an id so they can be referenced in commits
and issues. Status: `doing`, `next`, `planned`, `idea`, `waiting`.

## A. In flight

| Id | Item | Status | Notes |
|---|---|---|---|
| A1 | R CMD check + GPU integration suite on `post-training` (GRPO and pipeline tests included) | done | Gate for committing steps 5 and 6. |
| A2 | Commit steps 5 and 6 (`dragon_reinforce()`, `dragon_pipeline()`) to `post-training` | done | After A1 passes. |
| A3 | Browser check of the new Pipeline tab | done | Module logic is unit-tested; the rendered panel is not yet seen. |
| A4 | Restart the review app on port 3939 from the branch | done | The running instance predates steps 3 to 6. |

## B. Release 0.2.0

| Id | Item | Status | Notes |
|---|---|---|---|
| B1 | Merge `post-training` into `main` | done | Six commits ahead; all stages, eval, synthesis, pipelines. |
| B2 | Retitle NEWS "development version" to 0.2.0, bump DESCRIPTION | done | |
| B3 | Full tarball with vignettes, `R CMD check --as-cran`, win-builder devel + release | done | The check now also flags the dragonfarm.dev URL as unreachable until DNS exists (G2). | Pandoc is installed; same flow as 0.1.1. |
| B4 | Vignette for the post-training loop (train, synthesize, prefer, judge, compare) | done | The quickstart covers fine-tuning only. |
| B5 | Vignette for reinforcement learning with rewards | done | Include when GRPO helps and when it does not. |
| B6 | Tag v0.2.0 on GitHub; R-universe rebuilds on its own | done | |
| B7 | CRAN: submit 0.2.0 after 0.1.1 resolves | waiting | If the reviewer asks for changes to 0.1.1, answer with 0.2.0 rather than a 0.1.2. |

## C. Inference hosts

Training machines are rarely the right inference machines. Every inference
call today spawns a Python process that loads the model; this section
decouples where a model runs from where it trained.

| Id | Item | Status | Notes |
|---|---|---|---|
| C1 | `dragon_backend_local()` with a persistent worker that keeps the model loaded across calls | done | Removes the per-call model load in judge, synthesize, and Try it. |
| C2 | `dragon_backend_server(url, model)`: client for any OpenAI-compatible chat endpoint | done | Covers vLLM, llama.cpp server, Ollama, LM Studio, HF Inference Endpoints, RunPod and Modal vLLM templates. Streaming support for the chat UI (C8). |
| C3 | `dragon_serve_ollama(run)`: merge, register with Ollama by importing safetensors, return a backend | doing | Written; untested against a real Ollama (not installed here). | No GGUF step needed for Llama, Qwen2, Gemma families. Fastest local CPU inference. |
| C4 | `dragon_publish(run, repo)`: push merged model or adapter to the Hugging Face Hub | done | Hand-off to any hosted inference. Needs `HF_TOKEN`. |
| C5 | `backend` argument on `dragon_generate()`, judge and teacher wrappers, `dragon_synthesize_pairs()`, `dragon_judge()`; session default via `options(dragonfarm.backend)` | done | Local stays the default. |
| C6 | Try it panel: Publish card (repo, format, private) that pushes via `dragon_publish()` | done | Serve-with selector (this machine, Ollama, URL) already exists as the Chat tab's backend picker; a from-URL Try-it selector is folded into C7. |
| C7 | `dragon_deploy()` helpers for RunPod and Modal vLLM endpoints | idea | Both have configs on this machine; wraps publish (C4) plus a template launch and returns a backend. |
| C8 | Chat panel: multi-turn conversation with any backend, with context | planned | See section D. |

## D. Chat UI with context

A conversation view over an inference endpoint, in the app and as an R
function, so a trained model can be used the way it will be used.

| Id | Item | Status | Notes |
|---|---|---|---|
| D1 | `dragon_chat(backend)` in R: returns a conversation object that keeps message history; `$say()`, `$reset()`, `$history()` | done | Same message list format as training data, so transcripts can become data. |
| D2 | Multi-turn generation in the Python worker and the server client: send the full history each turn | done | Chat templates already handle multi-turn rendering. |
| D3 | App: Chat tab with message thread, system prompt, temperature, max tokens, backend selector, streaming replies | doing | Streaming reaches R (`on_token`); the Shiny panel shows whole replies for now. | Streaming via C2 for servers; token streaming from the local worker. |
| D4 | Context window handling: token count per turn, warn near the model's limit, drop or summarise oldest turns | planned | Small models have 2K to 8K contexts. |
| D5 | Side-by-side chat: same conversation sent to two backends or two runs (before and after a stage) | planned | Extends the existing base-versus-tuned comparison. |
| D6 | Feedback in the thread: thumbs up or down, edit a reply | done | Stored per turn with the run id. |
| D7 | Turn feedback into data: edited replies become SFT rows, up versus down on regenerated replies become preference pairs, exported as datasets for the next stage | done | `dragon_feedback()`. | Human-in-the-loop counterpart of `dragon_synthesize_pairs()`. |
| D8 | Save and load transcripts; export a conversation as a training example | planned | |

## E. Data and training

| Id | Item | Status | Notes |
|---|---|---|---|
| E1 | Multi-turn conversations as training data: a `messages` column holding whole conversations | done | `dragon_conversations()`. | Today rows are one prompt and one reply. |
| E2 | Data quality pass in `dragon_synthesize()`: dedupe, drop near-duplicates, length and language filters | done | |
| E3 | Teacher-distilled SFT from the model's own prompts plus a judge filter (keep only replies the judge scores above a threshold) | done | Folded into `dragon_synthesize(judge=, min_score=)` rather than a separate function. |
| E4 | `dragon_reinforce()`: tests as rewards (run a command or Python test against the completion) | idea | Common for code tasks; a `"command"` reward type. |
| E5 | `dragon_reinforce()`: optional length normalisation and reward clipping options exposed | idea | |
| E6 | Resume for GRPO restores the optimizer state, not just the adapter and step | idea | |
| E7 | Full-parameter fine-tuning for models under 500M | idea | Deliberately out of scope so far. |

## F. App and package polish

| Id | Item | Status | Notes |
|---|---|---|---|
| F1 | Run long app actions (evaluate, judge, synthesize) off the Shiny thread | done | They block the session today. Same pattern as pipelines: a background R process plus polling. |
| F2 | Cancel button for background pipelines | done | Record the pid; write a cancel request the runner checks between steps. |
| F3 | Delete and archive runs from the Monitor panel | idea | |
| F4 | Verify the Kaggle one-click notebook link | planned | Steps include the manual import fallback. |
| F5 | Live test of `dragon_llm_anthropic()` and `dragon_judge_anthropic()` with a real key | next | Only request shapes and fakes tested so far. |
| F6 | Live test of `dragon_llm_ellmer()` against one provider | planned | API calls verified against ellmer 0.5, no live call yet. |
| F7 | Persistent generation worker also serves the Try it panel (folds into C1) | planned | |
| F8 | Windows: investigate the occasional process-start failure (exit status -1073741502) under heavy load | idea | Seen twice when a second heavy process started during training. |

## G. Product and distribution

| Id | Item | Status | Notes |
|---|---|---|---|
| G1 | Decide the dragonfarm.dev layout: root as product site with R docs on `r.dragonfarm.dev`, or root as R docs | waiting | Decides what DNS points at. |
| G2 | DNS at Spaceship: A records to GitHub Pages addresses, CNAME for www | waiting | GitHub Pages already has the custom domain set. Paused on request. Until it resolves, CRAN's URL check flags the DESCRIPTION link. |
| G3 | Move pkgdown to a subdomain if G1 chooses the product-site layout | planned | |
| G4 | Product site (Cloudflare Pages or GitHub Pages): landing, R and Python quickstarts, cloud-GPU buttons, docs links | planned | |
| G5 | Python package `dragonfarm` on PyPI: extract `inst/python/dragonfarm`, add CLI (`train`, `check`, `generate`, `pack`) and a Python API over the run directory | planned | Name is free on PyPI and conda-forge. |
| G6 | R package 0.3 depends on the PyPI package through `py_require("dragonfarm==...")`, dropping the bundled copy | planned | After G5. |
| G7 | Gradio UI in the Python package mirroring the Shiny panels (`pip install dragonfarm[ui]`) | idea | |
| G8 | Hosted training on dragonfarm.dev (upload data, train on Modal, download adapter) | idea | Deferred until the static site and packages have users. |
| G9 | Announcement: email draft to David is ready; post once CRAN accepts | waiting | |

## H. Known rough edges

- Post-training sample generation takes about a minute for ten samples (C1 helps).
- Try it reloads the model per request (C1, F7).
- Background pipelines need serializable steps; ellmer chat objects cannot be judges in background mode.
- `dragon_evaluate(metrics = ...)` regenerates every held-out reply when fewer are saved; on large held-out sets that is slow.
- The GRPO loop keeps advantages zero for groups whose rewards do not vary, which wastes those samples; a curriculum that drops always-solved or never-solved prompts is a possible improvement.

## Ranked view (2026-09-16)

| # | Item | Priority | Value | Effort (days) |
|---|---|---|---|---|
| 1 | Land steps 5 and 6 (A1, A2) | P0 | High | 0.2 |
| 2 | Release 0.2.0 (B1 to B3, B6) | P0 | High | 0.5 |
| 3 | Live test of the Claude judge and teacher (F5) | P0 | High | 0.1 |
| 4 | Persistent local inference worker (C1) | P1 | High | 0.5 |
| 5 | Serve through Ollama (C3) | P1 | High | 0.5 |
| 6 | OpenAI-compatible client and `backend` argument (C2, C5) | P1 | High | 0.5 |
| 7 | Chat UI with context (D1 to D3) | P1 | High | 1.5 |
| 8 | Domain layout and DNS (G1, G2) | P1 | Medium | 0.1 |
| 9 | Vignettes for the loop and for RL (B4, B5) | P1 | Medium | 0.5 |
| 10 | Chat feedback becomes data (D6, D7) | P2 | High | 1 |
| 11 | App actions off the Shiny thread, pipeline cancel (F1, F2) | P2 | Medium | 1 |
| 12 | Publish to the Hub, Serve and Publish buttons (C4, C6) | P2 | Medium | 0.5 |
| 13 | Multi-turn data, quality filters, judged distillation (E1 to E3) | P2 | Medium | 1.5 |
| 14 | Python package, then R depends on it (G5, G6) | P2 | Medium | 2 |
| 15 | Product site (G4) | P2 | Medium | 1 |
| 16 | Chat polish: context limits, side-by-side, transcripts (D4, D5, D8) | P3 | Medium | 1 |
| 17 | Command rewards, GRPO options, optimizer resume (E4 to E6) | P3 | Medium | 1 |
| 18 | RunPod and Modal deploy helpers (C7) | P3 | Low | 0.5 |
| 19 | Housekeeping (F3, F4, F8) | P3 | Low | 0.5 |
| 20 | Gradio UI, hosted training, full fine-tuning (G7, G8, E7) | P3 | Low now | Large |

Items 4 to 7 are one arc (inference hosts, then chat) to do as a block after 0.2.0.
