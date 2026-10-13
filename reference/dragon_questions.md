# Write questions and answers from a document set

Turns documents into training data. For each chunk a model writes a few
self-contained questions and answers them from that chunk alone; simple
deterministic filters then mark pairs that are not grounded in the
chunk, name things the chunk does not, refer to "the passage", or
duplicate another question. Nothing is dropped: every pair comes back
with `keep` and, when rejected, a `reason`, so you can review them (the
Documents tab has a screen for it) before training with
[`dragon_questions_dataset()`](https://dragonfarm.dev/reference/dragon_questions_dataset.md).

## Usage

``` r
dragon_questions(
  docs,
  generator = NULL,
  n_per_chunk = 3,
  include_quotes = FALSE,
  include_code = TRUE,
  include_changelog = FALSE,
  load_in_4bit = "auto",
  batch_size = 4,
  max_new_tokens = 420,
  wait = TRUE
)

dragon_questions_progress(job)

dragon_questions_wait(job)
```

## Arguments

- docs:

  A `dragon_documents` object or its directory.

- generator:

  What writes the pairs. `NULL` uses the local model recommended for
  this machine (see
  [`dragon_check()`](https://dragonfarm.dev/reference/dragon_check.md));
  a model id uses that local model; a teacher such as
  [`dragon_llm_anthropic()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md),
  an `ellmer` chat, a run, or any function from prompts to replies is
  called from R instead. Local generation runs as a background Python
  process.

- n_per_chunk:

  Questions asked for per chunk.

- include_quotes, include_code, include_changelog:

  Which chunks to use. Block quotes are skipped by default (a quoted
  example reply is not your policy), code blocks are included,
  changelog-like sources are skipped.

- load_in_4bit:

  For a local generator: `"auto"`, `TRUE`, or `FALSE`; see
  [`dragon_backend_local()`](https://dragonfarm.dev/reference/dragon_backend.md).

- batch_size, max_new_tokens:

  Local generation settings.

- wait:

  Block until done. With `FALSE`, a local generation returns a job to
  poll with `dragon_questions_progress()` and finish with
  `dragon_questions_wait()`; a teacher always runs to completion.

- job:

  A job from `dragon_questions(wait = FALSE)`.

## Value

A `dragon_questions` data frame: `id`, `chunk_id`, `source`, `section`,
`question`, `answer`, `keep`, `reason`, `decided_by`, with the file it
was saved to in `attr(, "path")` and the set in `attr(, "documents")`.
Edit `keep` and
[`dragon_questions_save()`](https://dragonfarm.dev/reference/dragon_questions_load.md)
it.

## Details

Review them. On the package's own documentation about 60 percent of a 7B
model's pairs were usable, 33 percent of a 3B's, 20 percent of a 1.5B's,
and a fifth of what passed the filters was still wrong or trivial.
Quoted material and changelog-like sources are skipped by default
because they produced the worst pairs.

## Examples

``` r
if (interactive()) {
docs <- dragon_documents("policies/")
qa <- dragon_questions(docs)                      # local model, background, waits
qa                                                # how many kept, and why not
qa$keep[qa$id == "p0007"] <- TRUE                 # rescue one after reading it
dragon_questions_save(qa)
ds <- dragon_questions_dataset(qa, docs)          # excerpts retrieved into every prompt
run <- dragon_train(ds, "Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)
}
```
