# RAG prototype: results

Question: on the example support tickets, does adding retrieval of policy
documents help a LoRA fine-tuned `Qwen2.5-0.5B-Instruct`, and does it let
answers follow documents that change after training?

Setup (everything here is reproducible from this folder, see the end):

- **Knowledge base**: 29 short hand-written policy chunks (`kb.jsonl`): 3 per
  ticket category plus 8 unrelated ones.
- **Retrieval**: `BAAI/bge-small-en-v1.5`, top 5, mean-pooled with plain
  `transformers`. On 56 unseen tickets it put a right-category chunk in the top
  5 for 98% of tickets (and about 90% of that category's chunks); BM25 got 96% / 75%,
  MiniLM-L6 95% / 83% (`retrieval_results.json`).
- **Test tickets**: 56 tickets (8 per category) that never appear in the
  package's example data (`eval_tickets.jsonl`).
- **Conditions** (temperature 0, up to 220 new tokens):
  `base_plain` base model, plain prompt; `ft_plain` the standard fine-tuned run
  (190 tickets), plain prompt; `base_rag` base model + excerpts + an instruction
  to use only them; `ft_rag` the same fine-tuned model with excerpts added at
  inference only; `ragtuned` a new fine-tune whose training prompts include the
  retrieved excerpts (same model, LoRA, and training settings; only the prompt
  differs).
- **Scoring** is automatic: *fact recall* is the share of each category's key
  facts (regex checklist in `eval_conditions.py`) found in the reply;
  *unsupported* is the share of replies stating a duration, version, or
  number that is in neither the category's policy text nor the ticket.

## Results (56 unseen tickets)

| Condition | Fact recall | Unsupported numbers | Words |
|---|---|---|---|
| Base model | 9% | 9% | 169 |
| Base model + retrieval | 42% | 16% | 100 |
| Fine-tuned | 68% | 27% | 92 |
| Fine-tuned + retrieval at inference | 73% | 21% | 98 |
| **Fine-tuned with retrieval in training (RAG-tuned)** | **89%** | **4%** | 94 |

## Policy changed after training

The knowledge base was edited (return window 30 to 45 days; damaged-unit
turnaround 2 to 3 business days; warranty 2 to 3 years; app fix 4.12.2 to
4.13.0) and 32 unseen tickets from those four categories were answered with
the new excerpts. "New" is the share of replies in these categories that state
the new value, "stale" the share that still state the old one.

| Condition | New value | Old value | Unsupported numbers |
|---|---|---|---|
| Base model + retrieval | 22% | 0% | 3% |
| Fine-tuned + retrieval at inference | 6% | 35% | 47% |
| **RAG-tuned** | **88%** | **0%** | **0%** |

## Reading it

- Fine-tuning on its own is already far better than retrieval on a small base
  model here (68% vs 42% recall), because the model learns the reply format
  and wording as well as the facts.
- Retrieval only helps a model that was trained to use it. Adding excerpts to
  an ordinary fine-tuned model barely moves recall (73%) and, once the policy
  changes, it keeps stating the old one (35% of replies) and invents numbers
  (47%). It ignores the new context.
- Training with excerpts in the prompt gave the best of both: highest recall,
  almost no invented numbers, and it followed the changed policy in 88% of
  replies without retraining.
- The remaining misses are mostly retrieval misses (a needed chunk not in the
  top 5), not generation errors.

## Caveats

- 56 tickets (32 in the changed-policy test), one training run, one seed.
  Differences of a few points are noise; the large gaps are not.
- The data and the documents are synthetic and templated, and I wrote the
  knowledge base knowing the facts in the replies, so every number here is
  optimistic. Real documents are longer, messier, and less aligned with the
  questions.
- Scoring is a keyword checklist plus a number check. It does not judge
  whether a reply is correct in context or well written.
- The knowledge base is hand-written. Nothing here tests document
  ingestion, chunking, or automatic question generation, which are the
  hardest parts of a "drop in documents" feature.

## Reproduce

From this folder, with dragonfarm's Python environment (`python` below):

```
Rscript make_eval_tickets.R            # from the repo root; unseen tickets
python eval_retrieval.py               # retrieval comparison
python build_context.py                # retrieved excerpts for train and test
Rscript train_rag_tuned.R              # from the repo root; ~4 minutes on a laptop RTX 4060
python eval_conditions.py gen <condition> [--adapter RUN/adapter] [--changed]
python eval_conditions.py score
```

Do not train and generate at the same time on an 8 GB GPU: both runs ran out of
memory when I did.
