# Documents: design note

Status: agreed 2026-10-12, implementation starts with 0.4.0. Decisions in this
note were taken by Tejas on 2026-10-12 after the two prototypes in
`scripts/rag_prototype/` and `scripts/doc_prototype/` (read their
`RESULTS.md` first; every default below comes from a number there).

## What it is

dragonfarm turns your material into a small model that is yours: it answers
in your domain and your voice, and it loads anywhere with plain
`transformers`. From 0.4.0, **documents are the primary way in.** Drop in
PDFs, pages, Word files, or spreadsheets; dragonfarm reads them, builds the
training data for you, and fine-tunes. A table of prompt and response rows
remains available as the alternative route for people who already have one,
chosen explicitly, not the default.

Retrieval is the engine that makes the document route work, in two places:

1. **Before training**, it answers questions from the documents straight
   away, with cited sources, so the user can check that the material came
   through correctly, and gets value in the first minute.
2. **During and after training**, retrieved excerpts go into every training
   prompt and every answer. That is the setup that won in the ticket
   prototype (89% fact recall against 68% for a plain fine-tune), and it is
   what lets a fine-tuned model follow documents that change later without
   retraining: the model learns the style and how to use the excerpts; the
   documents stay the source of truth.

The one hard lesson from the document prototype is **do not fine-tune on
unreviewed machine-written pairs.** Seventy such pairs barely helped a 0.5B
model and taught it to sound sure when wrong. So the flow puts a review
screen between the documents and the Train button, and keeps the question
box open in the meantime. The destination is still a fine-tuned model.

## Decisions

| Question | Decision |
|---|---|
| Name | **Documents**: tab "Documents", functions `dragon_documents()`, `dragon_index()`, `dragon_ask()`, `dragon_pairs()` |
| Placement | Documents is tab 1 and the default path. The table route lives behind a "Have a table instead?" link that opens the Data and Map steps; those steps are hidden from the stepper until chosen. Step 1 of the six-step story becomes "Documents" |
| Default mode | Ask first (no training yet), then Generate pairs, Review, Train. The Train button is reachable only through the review screen |
| File types, v1 | PDF, HTML, Markdown, plain text, DOCX, web URLs (fetched as HTML), spreadsheets (xlsx/csv treated as documents: one chunk per row group or sheet) |
| Answer model | `Qwen/Qwen2.5-1.5B-Instruct` when nothing is trained; any run or base model can be chosen |
| Q&A generator | Local `Qwen/Qwen2.5-3B-Instruct` by default; an optional teacher via `dragon_llm_anthropic()` / `dragon_llm_ellmer()` when given, same pattern as `dragon_judge()` |
| Citations | Numbered footnotes with expandable excerpts (file, section, text); the same structure is returned by `dragon_ask()` |
| Persistence | Under `runs_dir/documents/<name>/`; temporary by default like runs, kept when `dragonfarm.runs_dir` is set; re-index only changed files |

## R API

```r
docs <- dragon_documents(c("policies.pdf", "https://example.com/faq", "handbook/"),
                         name = "support-kb")          # read, chunk, index; returns a dragon_documents object
docs                                                   # 3 sources, 142 chunks, indexed with bge-small, 2026-10-21

ans <- dragon_ask(docs, "How long is the return window?")
ans                                                    # prints the answer followed by [1] [2] footnotes
ans$sources                                            # data.frame: n, file, section, text, score
ans <- dragon_ask(docs, "...", model = run)            # answer with a fine-tuned run instead of the default base model
chat <- dragon_chat(run, documents = docs)             # every turn is answered with retrieved excerpts

pairs <- dragon_pairs(docs, n_per_chunk = 3)           # generated Q&A with filter verdicts; nothing dropped silently
pairs <- dragon_pairs(docs, teacher = dragon_llm_anthropic())
dragon_review(pairs)                                   # opens the review screen (same component as the app tab)
kept <- pairs[pairs$keep, ]

run <- dragon_train(kept, "Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)   # kept pairs are already a mapped dataset
                                                                       # with the retrieved excerpts in the prompt
```

Lower-level pieces, exported because the app and the pipeline need them:

- `dragon_index(docs, model = "BAAI/bge-small-en-v1.5")`: build or refresh the embedding index. Called by `dragon_documents()`; exposed for re-indexing after edits.
- `dragon_retrieve(docs, query, k = 4)`: the chunks alone, no generation. Used by the Chat toggle, by `dragon_pairs()` to build training prompts, and in tests.
- `dragon_documents_load(dir)` / `dragon_documents_list(runs_dir)`: reopen by name.

`dragon_pairs()` returns a data frame with `question`, `answer`, `chunk_id`,
`source`, `keep` (logical, the filter verdict) and `reason` (why a pair was
rejected). Rejected pairs stay in the table so the review screen can show
them and the user can rescue one. The mapped dataset it carries uses the
prompt template `"Documentation excerpts:\n{context}\n\nQuestion: {question}"`
where `context` is what `dragon_retrieve()` returns for the *question*, not the
chunk the pair was written from, so training matches answer time.

## On disk

```
<runs_dir>/documents/<name>/
  manifest.json      sources (path or URL, sha256, size, mtime, reader, chunk count), index model, created/updated
  chunks.jsonl       id, source, section, text, n_words, page (PDF) or row range (spreadsheets)
  index/             embeddings.npy (float16, one row per chunk) + ids.json
  pairs/<stamp>.jsonl   generated pairs with keep/reason; one file per generation run
  questions.jsonl    every dragon_ask() call: question, answer, source ids, model, time (opt-out via option)
```

Everything is plain files, like runs: inspectable, copyable to a cloud GPU
with `dragon_bundle()`, readable from Python through `dragonfarm.api`.

## Python side (`inst/python/dragonfarm/`)

New modules, all driven through the existing worker protocol
(`worker.py` ops `ping`/`unload`/`quit`/`generate`) so the index model stays
loaded between calls:

- `documents.py`: readers (pypdf for PDF, `html.parser` for HTML, python-docx for DOCX, openpyxl for xlsx, csv for csv, stdlib for Markdown/text; URLs fetched with `urllib` and passed to the HTML reader), heading-aware chunker (target 170 words, min 35, headings start a new chunk, short sections folded into the previous one), glyph and page-furniture stripping. Ports `scripts/doc_prototype/ingest.py`.
- `retrieval.py`: mean-pooled embeddings via plain `transformers` (no sentence-transformers dependency), float16 on disk, cosine top-k. New worker ops `index`, `retrieve`.
- `pairs.py`: generation prompt and filters (grounding ratio with stemming, unknown-identifier check, "the passage" check, length, duplicates). Ports `scripts/doc_prototype/qa_gen.py`. Worker op `pairs`, streaming progress through the usual `progress.jsonl` so the app can show a bar.

New requirements in `dragon_python_requirements()`: `pypdf`, `python-docx`,
`openpyxl`. All pure Python, small, no compiled extensions.

## App

The document route is the default sequence of tabs: **1 Documents, 2 Model,
3 Train, 4 Monitor, 5 Try it, 6 Chat, 7 Pipeline.** Data and Map are not in
that sequence. A "Have a table instead?" link on the Documents tab (and a
`dragon_app(route = "table")` argument for people who always use tables)
switches the navbar to the table route: 1 Data, 2 Map, 3 Model, and so on,
which is today's app unchanged. The route is remembered per session; the
state object gains `route = "documents" | "table"` and the Model tab's
"what will be trained" summary reads from whichever route is active.

Documents tab, left to right:

1. **Sources card**: drop zone for files, a URL field, the list of loaded sources with chunk counts, and "Index" (automatic after a drop). A document set name field; "Open" lists saved sets.
2. **Ask card**: question box, model picker (default the 1.5B; any run from Monitor), answer with `[n]` chips that expand to the excerpt. "Send to Chat" opens the Chat tab with the documents toggle on.
3. **Teach card** (open, below Ask): "Generate questions and answers" with generator choice (local 3B, or a teacher when a key is present), progress bar, then the **review screen**: pairs grouped by chunk, a checkbox per chunk and per pair, rejected pairs shown greyed with their reason, yield counter ("48 of 150 kept"). "Continue to Model" loads the kept pairs as the mapped dataset (excerpts already in the prompts) and moves to tab 2. This is the main path through the app.

Chat and Try it answer with retrieved excerpts automatically when the run was
trained from documents, and show the same footnotes; for table-trained runs
a document set can be attached with a picker.

The hero stepper, GIF, README steps, and the quickstart all become the
document route: Documents, Model, Train, Monitor, Try it, Chat. The table
route gets one line ("Already have prompt and response rows? Load a table
instead.") and its own short article. The site gets an article "From your
documents to your model" with the prototype numbers.

## Guardrails learned from the prototypes

- **Quoted examples contaminate pairs.** The README's quoted support reply became "what if my Lumen bulb pack is damaged?" pairs in both generators. The chunker marks blockquotes and fenced examples; `dragon_pairs()` skips them by default (`include_quotes = FALSE`), and the review screen groups by chunk so a whole bad chunk is one click to drop.
- **Changelog-style files crowd out answers.** Files named NEWS, CHANGELOG, HISTORY, or whose chunks are mostly dated bullet lists are indexed but down-weighted (score x 0.7) and flagged in the sources list; the user can turn that off.
- **PDF tables flatten.** v1 ships with pypdf and says so in the sources list ("tables in this PDF may read poorly"). A layout-aware extractor is a follow-up, gated on Tejas's real-document test (plan row, Jan 8).
- **Small tuned models sound sure when wrong.** The Teach card shows the prototype numbers next to the button, and the article says plainly that answering from documents beats fine-tuning on auto-generated pairs unless the pairs were reviewed.
- **Eval OOM on long prompts.** Retrieval prompts are ~700 tokens, so `max_seq_len` defaults to 1024 for document training and the end-of-run evaluation runs with batch size 1 (the fix for the bug the prototype hit; it is independent of this feature and ships first).
- **Never train and generate on the same GPU at once.** The app already stops the worker before launching a trainer; `dragon_pairs()` must do the same, and the Teach card disables "Generate" while a run is training.

## Testing

- Unit: readers on fixture files (one tiny PDF, HTML, DOCX, xlsx, md, csv in `tests/testthat/fixtures/documents/`), chunker edge cases (headings, short sections, code fences, glyphs), filters on hand-written good/bad pairs, manifest round trip, change detection.
- Integration (GPU, `DRAGONFARM_INTEGRATION=true`): index the package's own docs, ask the 35 gold questions from `scripts/doc_prototype/gold.jsonl`, require hit@4 >= 0.75 and answered >= 0.5 with the 1.5B; generate pairs for 5 chunks and require at least one kept.
- App: `shiny::testServer` for the Documents module (drop, index, ask, generate, review toggles, hand-off to Model).

## Out of scope for 0.4.0

OCR for scanned PDFs; images and slides; multilingual embedding models; a
hosted index service; re-ranking models; hybrid BM25 + dense retrieval
(BM25 was 10 points behind bge-small on hit@5 and adds little once dense
retrieval is in; revisit if users bring very long or jargon-heavy corpora).

## Schedule (from the 90-day plan)

| Due | Deliverable |
|---|---|
| Oct 16 | This note; eval OOM fix |
| Oct 21 | `dragon_documents()` + readers + chunker + manifest |
| Oct 28 | `dragon_index()`, `dragon_retrieve()`, `dragon_ask()`; Chat/Try it toggle |
| Nov 4 | Documents tab (Sources + Ask cards) |
| Nov 6 | Tejas tests on real documents |
| Nov 11 | `dragon_pairs()`, review screen, Teach card, hand-off to training |
| Nov 18 | Article, README, hero/GIF step 1, quickstart |
| Nov 24 | Launch (dev version via pak) |
| Dec 7–10 | 0.4.0 to CRAN with the feature |
