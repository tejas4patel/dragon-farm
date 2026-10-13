# A hand-written question set inside a fake document set (see helper-documents.R).
write_fake_questions <- function(dir, stamp = "20261012-120000") {
  qdir <- file.path(dir, "questions"); dir.create(qdir, showWarnings = FALSE)
  path <- file.path(qdir, paste0(stamp, ".jsonl"))
  rows <- list(
    list(id = "p0001", chunk_id = "abc-000", source = "policy.pdf", section = "Returns", question = "How long is the return window?",
         answer = "Thirty days from delivery.", keep = TRUE, reason = NULL, decided_by = "filter"),
    list(id = "p0002", chunk_id = "abc-000", source = "policy.pdf", section = "Returns", question = "What does the passage say?",
         answer = "Thirty days.", keep = FALSE, reason = "refers to the passage", decided_by = "filter"),
    list(id = "p0003", chunk_id = "abc-001", source = "policy.pdf", section = "Warranty", question = "How long is the warranty?",
         answer = "Two years from delivery.", keep = TRUE, reason = NULL, decided_by = "filter")
  )
  dragonfarm:::write_jsonl(rows, path)
  dragonfarm:::write_json(list(generator = "Qwen/Qwen2.5-7B-Instruct", n_pairs = 3L, n_kept = 2L, unparsed = 0L), paste0(path, ".meta.json"))
  path
}
