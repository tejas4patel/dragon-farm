# Quickstart: from documents to a model, in R

dragonfarm turns your material into a small language model that is
yours: it answers in your domain and your voice, and it loads anywhere
with plain `transformers`. This page walks the default route once, on
the example documents that ship with the package: read documents, ask
them questions, have a model write training questions, review them,
fine-tune, compare. The same six steps are the tabs of the app
([`dragon_app()`](https://dragonfarm.dev/reference/dragon_app.md)).

If your data is already a table of prompts and replies, skip to [the
table route](#the-table-route) at the end.

## 1. Check the machine

``` r

library(dragonfarm)
dragon_check()
```

The first call builds a Python environment with torch and transformers.
That is a 2 to 3 GB download and takes a few minutes; later calls take a
second. The report names the device, whether 4-bit loading is available,
and the model it will use by default to answer questions on this
machine: a 1.5B model under 6 GB of GPU memory or on a CPU, a 3B at 6 to
8 GB, a 7B in 4-bit at 8 GB and up.

Keep your sets and runs somewhere permanent; by default they live under
a temporary folder and vanish with the session:

``` r

options(dragonfarm.runs_dir = "~/dragonfarm_runs")
```

## 2. Read the documents

``` r

docs <- dragon_documents(dragon_example_documents(), name = "policies")
docs
#> Document set policies
#> • returns-and-warranty.md: 3 chunks, 328 words
#> • connectivity-and-app.md: 3 chunks, 360 words
#> • orders-and-support.md: 3 chunks, 389 words
#> 9 chunks of about 170 words; index: BAAI/bge-small-en-v1.5
```

The example is three short Markdown files of support policies for a
fictional smart-home company (the same company as the example tickets).
Your own PDF, HTML, Word, text, and spreadsheet files, folders of them,
and web pages work the same way:
`dragon_documents(c("policies/", "https://..."))`. Text is split into
chunks that never cross a heading, each remembering its file and
section, and embedded with a small model (downloaded once, about 130
MB). Reading the same set again re-reads only files that changed.

## 3. Ask

``` r

ans <- dragon_ask(docs, "How long is the return window?")
ans
#> Any device can be returned within 30 days of delivery, opened or unopened, for a full refund [1].
#>
#> [1]* returns-and-warranty.md › Returns
#> [2]  returns-and-warranty.md › Damaged on arrival
#> [3]  orders-and-support.md › Cancelling an order
#> [4]  returns-and-warranty.md › Warranty
#> * cited in the answer. Excerpt text is in $sources$text.
```

The most relevant chunks go in front of the model as numbered excerpts,
with an instruction to answer only from them and to cite them. The first
question in a session loads the model (about a minute for a 7B in
4-bit); later ones take seconds. For many uses this step is the whole
job: nothing is trained, and you can swap the documents and ask again.
`dragon_chat(documents = docs)` does the same with memory across turns.

## 4. Write training questions, and review them

``` r

qa <- dragon_questions(docs)
#> 27 questions written, 16 kept by the filters (59%). Review them before training.
qa
```

For every chunk a model writes three self-contained questions and
answers them from that chunk alone; deterministic filters then mark
pairs that are not grounded in the chunk, name things it does not, refer
to “the passage”, or repeat another question. Nothing is thrown away:
each pair has `keep` and a `reason`. On a CPU, pass a small generator
such as `generator = "Qwen/Qwen2.5-0.5B-Instruct"` and expect to keep
few; on a GPU the default is the machine’s recommended model, and a
stronger teacher such as
[`dragon_llm_anthropic()`](https://dragonfarm.dev/reference/dragon_llm_anthropic.md)
keeps more.

Now read them. This is the step that decides whether the fine-tune is
worth having: in our tests, roughly a fifth of the pairs that passed the
filters were still wrong or trivial, and a model trained on unreviewed
pairs learned to sound sure when it was wrong.

``` r

qa[!qa$keep, c("question", "reason")]     # what was rejected, and why
qa$keep[qa$id == "p0007"] <- TRUE          # rescue one you like
dragon_questions_save(qa)                  # decisions stay with the set
```

In the app this is the Teach card: tick and untick, Save decisions,
Continue to Model.

## 5. Fine-tune

``` r

ds <- dragon_questions_dataset(qa, docs)   # kept pairs, with retrieved excerpts in every prompt
run <- dragon_train(ds, "HuggingFaceTB/SmolLM2-135M-Instruct",
                    lora = dragon_lora(r = 8, alpha = 16),
                    args = dragon_train_args(epochs = 2, batch_size = 2, grad_accum = 4, max_seq_len = 1024),
                    wait = TRUE)
```

Each training prompt is the excerpts retrieved for that question, then
the question; the answer is the response. The model learns the style and
how to use excerpts, and the documents stay the source of truth, so they
can change later without retraining. The 135M model trains on a CPU in a
few minutes; on a GPU, `Qwen/Qwen2.5-0.5B-Instruct` is the better
default. With `wait = TRUE` you get a progress bar; without it the
function returns at once and `dragon_status(run)`,
`dragon_progress(run)`, and `dragon_wait(run)` follow along. Runs
survive the session: `dragon_run("~/dragonfarm_runs/<id>")` reopens one.

## 6. Compare and use

``` r

dragon_ask(docs, "Can I return a device I have already set up?", model = run)
dragon_ask(docs, "Can I return a device I have already set up?", model = run, base = TRUE)   # what it started from
dragon_evaluate(run)                        # held-out loss and sample replies
chat <- dragon_chat(run, documents = docs)  # a conversation, answering from the documents
chat$say("A customer wants to return an opened device.")
dragon_merge(run, "models/policies-135m")   # a standalone model for plain transformers
```

A 135M model trained on sixteen pairs will not impress you; this run is
to see the parts move. Use a bigger base model, your own documents, and
a reviewed set of a few hundred pairs for a result you would keep. The
measured numbers behind each step, and what to expect from each model
size, are in [From your documents to your
model](https://dragonfarm.dev/articles/documents.html).

## The table route

If your data already comes as rows of prompt and response, start from a
table instead. The bundled example tickets have `subject`, `body`, and
`reply` columns:

``` r

ds <- dragon_dataset(dragon_example_data()) |>
  dragon_map(prompt = "{subject}\n\n{body}", response = "reply")
dragon_preview(ds, n = 1)                   # the first row exactly as the model sees it
run <- dragon_train(ds, "HuggingFaceTB/SmolLM2-135M-Instruct", wait = TRUE)
dragon_generate(run, "Charged twice for Sentry doorbell\n\nMy card shows two charges for one order.")
```

[`dragon_map()`](https://dragonfarm.dev/reference/dragon_map.md) takes
column names or templates that combine columns, and an optional
`system =`. Everything after that is the same: evaluate, chat, merge,
publish. In the app, “Have a table of prompts and replies instead?” on
the Documents tab switches to this route, where the Map step is drag and
drop.

## Choosing settings

**Model.** Start with `HuggingFaceTB/SmolLM2-360M-Instruct` or
`Qwen/Qwen2.5-0.5B-Instruct`. Move up only if quality is not enough; for
answering from documents, a bigger *base* model with retrieval often
beats a small fine-tuned one.

**Rank.** 8 to 16 is plenty for format and tone. Go to 32 or 64 when the
model must learn a lot of new facts.

**Learning rate.** 2e-4 for LoRA. Halve it if the loss curve is jagged.

**Epochs.** 2 to 3. Watch the eval loss: if it rises while training loss
falls, stop earlier.

**Sequence length.** Long enough for your longest prompt plus reply;
document prompts with four excerpts need about 1024 tokens. Shorter is
faster and uses less memory.

**Out of memory?** Lower `batch_size`, raise `grad_accum` to compensate,
and turn on `gradient_checkpointing`.
