# The FDA guidance example, end to end with the public API.
# Usage, from the package root: Rscript scripts/fda_example/fda_pipeline.R <step>
# step = questions | train | ask. Expects the document set "fda-stats" read from the
# four PDFs listed in vignettes/articles/fda-guidance.Rmd. Results go to
# ~/dragonfarm_runs/fda-example.
suppressMessages(devtools::load_all(".", quiet = TRUE))
options(dragonfarm.runs_dir = path.expand("~/dragonfarm_runs"))
W <- path.expand("~/dragonfarm_runs/fda-example"); dir.create(W, showWarnings = FALSE, recursive = TRUE)
source("scripts/fda_example/fda_questions.R")
say <- function(...) { m <- sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), paste0(...)); cat(m, "\n"); cat(m, "\n", file = file.path(W, "fda_log.txt"), append = TRUE) }
step <- commandArgs(trailingOnly = TRUE)[1]
docs <- dragon_documents_load("fda-stats")

if (step == "questions") {
  t0 <- Sys.time()
  qa <- dragon_questions(docs)                       # the recommended local model writes them (7B in 4-bit here)
  dragon_questions_save(qa)                          # keep the filters' decisions as the review
  saveRDS(qa, file.path(W, "fda_qa.rds"))
  say(sprintf("questions: %d pairs, %d kept, %.1f min", nrow(qa), sum(qa$keep), as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

if (step == "train") {
  qa <- readRDS(file.path(W, "fda_qa.rds"))
  ds <- dragon_questions_dataset(qa, docs)
  t0 <- Sys.time()
  run <- dragon_train(ds, "Qwen/Qwen2.5-3B-Instruct", name = "fda-stats-3b",
                      hardware = dragon_hardware(load_in_4bit = TRUE),
                      args = dragon_train_args(batch_size = 1, grad_accum = 16, gradient_checkpointing = TRUE, max_seq_len = 1536),
                      wait = TRUE)
  writeLines(run$dir, file.path(W, "fda_run.txt"))
  st <- dragon_status(run)
  say(sprintf("train: %s, %d rows, state %s, %.1f min", run$id, nrow(ds$data), st$state, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

if (step == "ask") {
  REFUSAL <- paste0("(do(es)?( not|n't)|did not|didn't) (cover|mention|contain|provide|include|specify|say|state|address|have|give|discuss|list|offer)",
                    "|not (covered|mentioned|provided|available|included|specified|addressed|found|discussed|listed)",
                    "|no (information|mention|details|data)|cannot (find|answer|determine|be determined)|unable to")
  run <- dragon_run(readLines(file.path(W, "fda_run.txt")))
  who <- list("3B base" = list(model = run, base = TRUE), "3B trained" = list(model = run, base = FALSE),
              "7B base" = list(model = "Qwen/Qwen2.5-7B-Instruct", base = FALSE))
  rows <- list()
  for (lab in names(who)) {
    w <- who[[lab]]
    qs <- rbind(data.frame(question = FDA_QUESTIONS$question, pattern = FDA_QUESTIONS$pattern, kind = "answerable"),
                data.frame(question = FDA_UNANSWERABLE, pattern = NA_character_, kind = "unanswerable"))
    for (i in seq_len(nrow(qs))) {
      t0 <- Sys.time()
      a <- tryCatch(dragon_ask(docs, qs$question[i], model = w$model, base = w$base), error = function(e) list(answer = paste("ERROR:", conditionMessage(e))))
      ans <- a$answer %||% ""
      ok <- if (qs$kind[i] == "answerable") grepl(qs$pattern[i], ans, perl = TRUE) else grepl(REFUSAL, ans, ignore.case = TRUE, perl = TRUE)
      rows[[length(rows) + 1]] <- data.frame(model = lab, kind = qs$kind[i], question = qs$question[i], ok = ok,
                                             seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")), answer = ans)
    }
    r <- do.call(rbind, rows); r <- r[r$model == lab, ]
    say(sprintf("ask %s: right %d/%d, declined %d/%d, median %.1fs, median words %.0f", lab,
                sum(r$ok[r$kind == "answerable"]), sum(r$kind == "answerable"), sum(r$ok[r$kind == "unanswerable"]), sum(r$kind == "unanswerable"),
                median(r$seconds), median(lengths(strsplit(trimws(r$answer[r$kind == "answerable"]), "[[:space:]]+")))))
    dragon_worker_stop()
  }
  saveRDS(do.call(rbind, rows), file.path(W, "fda_answers.rds"))
}
