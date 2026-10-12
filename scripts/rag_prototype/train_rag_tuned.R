# Fine-tune with the retrieved policy excerpts in the prompt ("RAG-tuned").
# Same model, LoRA settings, and training settings as the plain example run;
# only the prompt differs. Run from the repo root after build_context.py.
library(dragonfarm)
tr <- jsonlite::stream_in(file("scripts/rag_prototype/train_with_context.jsonl"), verbose = FALSE)
tr <- tr[, c("subject", "body", "context", "reply")]
run <- dragon_dataset(tr) |>
  dragon_map(prompt = "Policy excerpts:\n{context}\n\nTicket:\n{subject}\n\n{body}",
             response = "reply") |>
  dragon_train("Qwen/Qwen2.5-0.5B-Instruct", name = "rag-tuned", wait = TRUE,
               runs_dir = "~/dragonfarm_runs")
print(run$dir)
