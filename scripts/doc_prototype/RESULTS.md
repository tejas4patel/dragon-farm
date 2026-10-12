# Document-ingestion prototype: results

Question: can a user drop in documents (PDF, HTML, Markdown) and get a model
that answers questions about them, with no column mapping and no hand-written
training data? This prototype runs that whole path on dragonfarm's own
documentation and measures each stage. Everything ran locally on a laptop
RTX 4060 (8 GB); nothing left the machine.

## The corpus

Ten files in `corpus/`: two articles printed to PDF from dragonfarm.dev
(`under-the-hood`, `cloud-gpu`), six article pages saved as HTML, and the
package's README.md and NEWS.md. 7,000 words in total. The gold set is 35
questions I wrote from reading the documents (`gold.jsonl`), each with the
regexes an answer must match.

## Stage 1: documents to chunks (`ingest.py`)

70 chunks, median 100 words, each keeping its source file and section
heading. HTML and Markdown come through clean. PDF is the weak link:
`pypdf` flattens the models table in `under-the-hood.pdf` into a single
230-word run of text, and the cloud-provider table in `cloud-gpu.pdf` into a
jumble of cells and code. Both are still retrievable but hard to answer from.
Icon-font glyphs and page furniture ("dragonfarm 0.3.4", "On this page") also
leak in and had to be stripped.

## Stage 2: retrieval (`eval_docs.py retrieval`)

`BAAI/bge-small-en-v1.5`, top 4, over the 70 chunks.

| | hit@1 | hit@2 | hit@4 |
|---|---|---|---|
| Gold chunk retrieved | 60% | 74% | 80% |

On the synthetic policy knowledge base in `../rag_prototype` the same
retriever reached 98% at k=5. The misses here come from the flattened PDF
tables (two questions), NEWS.md changelog chunks crowding out the article
that actually answers (three questions), and one question whose answer is in
a section heading rather than the text.

## Stage 3: automatic question-and-answer pairs (`qa_gen.py`)

A local instruct model writes three questions and answers per chunk
(NEWS.md excluded, 50 chunks). Automatic filters then drop pairs whose
answer is not grounded in the chunk, that refer to "the passage", that name
a function, file, or version not in the chunk, or that duplicate another
question. I then read every surviving pair myself.

| Generator | Written | Pass filters | Usable on reading | Yield |
|---|---|---|---|---|
| Qwen2.5-1.5B-Instruct | 106 (14 chunks unparseable) | 34 | ~21 | ~20% |
| Qwen2.5-3B-Instruct | 150 | 70 | ~50 | ~33% |

What went wrong in the pairs that passed the filters:

- **Contamination from quoted examples.** The README quotes a support-ticket
  reply as a before-and-after demo. Both models turned it into "What should I
  do if my Lumen bulb pack arrives damaged?" pairs: fluent, grounded in the
  chunk, and nothing to do with the package. A real feature needs a way to
  exclude quoted material, or a review step where a person deselects chunks.
- **Plausible fact swaps.** "Google Colab gives about 30 GPU hours a week"
  (that is Kaggle), "all formats require the arrow package" (only Parquet
  does), "median word overlap of 10" (it was 10 tickets).
- **Trivial or link-only pairs** from the README's table of links and the
  app's two-line intro.

The 3B model is clearly the floor for this job. The filters catch the worst
cases, but about a quarter of what passes them is still wrong or useless, so
a review step before training is not optional.

## Stage 4: answering the 35 gold questions (`eval_docs.py gen/score`)

Every condition sees the same top-4 retrieved chunks (except the first row).
`answered` = reply matches every regex for the question. `fact in context` =
the retrieved chunks contained the answer at all (the ceiling for a faithful
model). `unsupported names` = reply names a function, file, or version that
is in neither the chunks nor the question. Temperature 0.

| Condition | Answered | Fact in context | Unsupported names | Words |
|---|---|---|---|---|
| 0.5B, no retrieval | 0% | — | 17% | 115 |
| 0.5B + retrieval | 49% | 80% | 3% | 19 |
| **0.5B fine-tuned on the 70 generated pairs, + retrieval** | **57%** | 80% | 6% | 21 |
| 1.5B + retrieval | 60% | 80% | 0% | 16 |
| 3B + retrieval | 69% | 80% | 0% | 21 |

The regexes are strict, so true accuracy is a few points higher, most of all
for the 3B (for example "asked twice with the roles reversed" is a correct
answer that misses the `swapped` pattern).

## Reading it

- **Retrieval does almost all the work.** Without it the 0.5B answers
  nothing correctly and invents function names in 17% of replies. With it,
  every model answers most of the questions whose answer was retrieved.
- **Fine-tuning on auto-generated pairs helped a little and cost something.**
  +8 points for the 0.5B, still below a 1.5B base model with the same
  retrieval, and the tuned model's misses are confidently wrong
  (`dragon_merge` "combines two runs"; an invented `dragon_logs` function)
  where the base model hedged or quoted. Seventy noisy pairs is not enough
  to teach facts, and it is enough to teach a model to sound sure.
- **Model size beats tuning at this scale.** 1.5B base + retrieval is better
  than 0.5B tuned + retrieval; 3B is better again and never invents a name.
- **This reverses the support-ticket result** in `../rag_prototype`, where
  training with retrieved context went from 73% to 89%. The difference is the
  training data: 190 clean, consistent, human-written pairs there; 70
  auto-generated, partly wrong pairs here. The method is fine. The data was
  not.

## What this means for a "drop in documents" feature

1. **Default to retrieval with no training.** It is instant, swaps documents
   without retraining, and a 1.5B or 3B base model answers well. Offer
   fine-tuning as a second step for style, or once a reviewed pair set
   exists.
2. **Question generation needs a 3B-class model at minimum and a review
   screen.** Show the pairs grouped by chunk, let the user untick chunks and
   pairs, and show the yield. A stronger generator (a local 7B, or an API
   model through `dragon_llm_*`) would raise the yield; I did not test one.
3. **Chunk quality decides retrieval quality.** Tables in PDFs need a real
   layout-aware extractor, and changelog-style files should be excluded or
   down-weighted by default.
4. **Package issue found on the way:** the end-of-run evaluation uses the
   training batch size, and at `max_seq_len = 1536` with batch 4 the logits
   alone (4 x 1536 x 152k vocab) ran a 0.5B model out of memory on 8 GB
   *after* training had finished. Training succeeded with batch 2 x accum 8.
   Correction, found later the same day: the GPU was not otherwise idle. An
   inference worker (`dragonfarm.worker`) left behind by the demo app had
   held a loaded model since the morning, which is why memory was tighter
   than it should have been. The evaluation tensor is still real and still
   the thing that tipped it over, and it has since been fixed (chunked loss,
   `eval_batch_size`, graceful fallback); but a second gap is that
   `launch_trainer()` only stops the *current session's* worker, not one
   owned by another R process such as the app.

## Addendum: a mid-sized model (Qwen2.5-7B-Instruct, 4-bit)

Run after the above, same chunks, same retrieved context, same gold
questions, same pair prompt and filters. The 7B does not fit an 8 GB GPU in
bf16 (15 GB), so it was loaded 4-bit NF4 through `bitsandbytes` 0.50.2,
quantised on the fly from the full download. (The pre-quantised
`unsloth/Qwen2.5-7B-Instruct-bnb-4bit` checkpoint fails to load under
transformers 5.19 with a tensor-size mismatch; on-the-fly quantisation of the
official weights works.)

**Answering the 35 gold questions** (retrieval, top 4):

| Model | Answered (regex) | Answered (read by hand) | Unsupported names |
|---|---|---|---|
| 1.5B bf16 | 60% | — | 0% |
| 3B bf16 | 69% | ~74% | 0% |
| **7B 4-bit** | **77%** | **~86%** | **0%** |

Reading the eight regex misses by hand: three are correct answers the
pattern missed (KL penalty, feedback datasets, which models need a token);
one is faithful to a retrieved code example rather than the prose the gold
wanted; and four are questions whose answer was *not* retrieved, where the
7B wrote "the documentation does not specify" instead of guessing. The
smaller models guessed on those. So the 7B answered essentially every
question whose chunk was in front of it, and declined the rest. The
remaining gap is retrieval, not the model.

**Generating pairs** (same 50 chunks, 3 per chunk):

| Generator | Written | Pass filters | Usable on reading | Yield |
|---|---|---|---|---|
| 1.5B | 106 | 34 | ~21 | ~20% |
| 3B | 150 | 70 | ~50 | ~33% |
| **7B 4-bit** | 150 | 111 | **~90** | **~60%** |

The 7B's pairs are noticeably more specific (they quote the right function
and argument) and far fewer are trivial. What did not go away: the three
"Lumen bulb pack" pairs generated from the README's quoted example reply,
one `dragon_merge` misreading, and a few link-only pairs from the README's
table. The quote guard and the review screen are needed at every size.

**Cost on this laptop (RTX 4060, 8 GB), each model alone in a fresh process,
~1,180-token prompts, 60 new tokens:**

| Model | Load | Weights in VRAM | Peak VRAM | One question | 8 questions batched |
|---|---|---|---|---|---|
| 1.5B bf16 | 7 s | 2.9 GB | 3.7 GB | 1.4 s (13 tok/s) | 3.0 s |
| 3B bf16 | 14 s | 5.9 GB | 6.9 GB | 2.0 s (10 tok/s) | 5.7 s |
| 7B 4-bit | 37 s | 5.5 GB | 7.2 GB | 2.8 s (8.5 tok/s) | 11.0 s |

A 4-bit 7B uses about the same memory as a bf16 3B and is about 40% slower
per token, for a large gain in answer quality and double the pair yield.
Download is 15 GB (the full weights; quantisation happens at load) against
6 GB for the 3B. It does not fit next to a training run on 8 GB, and it
leaves no room for anything else on a 6 GB card.

**What this changes in the recommendation:** the default pair generator and
default answer model should follow the hardware check: 1.5B below 6 GB, 3B
at 6 to 8 GB, 7B 4-bit at 8 GB and above (or whenever the user asks). That
requires 4-bit loading in the package, which the measurement shows works on
Windows with the environment dragonfarm already builds. Fine-tuning a 7B
(QLoRA) was not measured here.

## Caveats

- 35 questions, one corpus, one seed each. Differences under ~6 points
  (two questions) are noise.
- The corpus is dragonfarm's own documentation, which the base models have
  never seen, which is the honest case, but it is also short, well written,
  and in English.
- I both wrote the gold questions and graded the generated pairs, after
  reading the documents. A second reader would land on somewhat different
  "usable" counts.
- No API-model generator and no 7B local generator were tried; the 3B is
  the largest that fits comfortably next to training on this GPU.

## Reproduce

From this folder, with dragonfarm's Python environment as `python` and
`pypdf` available (`DF_PYLIBS` points at a folder containing it):

```
python ingest.py corpus chunks.jsonl
python eval_docs.py retrieval                            # DF_DEVICE=cpu to keep the GPU free
python qa_gen.py chunks.jsonl pairs_qwen3b.jsonl Qwen/Qwen2.5-3B-Instruct --bs 4
python build_train.py pairs_qwen3b.jsonl train_doc_rag.jsonl
Rscript scripts/doc_prototype/train_doc_rag.R            # from the repo root, ~2 minutes
python eval_docs.py gen base05_rag
python eval_docs.py gen base3b_rag --base Qwen/Qwen2.5-3B-Instruct
python eval_docs.py gen ragtuned05 --adapter <run>/adapter --no-system
python eval_docs.py score
```

Raw generator output is cached next to each `pairs_*.jsonl` so the filters
can be changed and re-run without regenerating.
