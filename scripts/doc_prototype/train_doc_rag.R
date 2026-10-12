# Fine-tune Qwen2.5-0.5B-Instruct on generated documentation Q&A with retrieved
# excerpts in the prompt. Run from the repo root after build_train.py.
library(dragonfarm)
tr <- jsonlite::stream_in(file("scripts/doc_prototype/train_doc_rag.jsonl"), verbose = FALSE)
run <- dragon_dataset(tr) |>
  dragon_map(prompt = "Documentation excerpts:\n{context}\n\nQuestion: {question}",
             response = "answer") |>
  dragon_train("Qwen/Qwen2.5-0.5B-Instruct", name = "doc-rag-tuned", wait = TRUE,
               runs_dir = "~/dragonfarm_runs",
               # batch 2 x accum 8 = the default 16 rows per step. With batch 4 the
               # end-of-run evaluation (eval batch = train batch) ran out of memory
               # on an 8 GB GPU: 4 x 1024 tokens x the 152k vocab of logits.
               args = dragon_train_args(epochs = 3, max_seq_len = 1024,
                                        batch_size = 2, grad_accum = 8))
print(run$dir)
