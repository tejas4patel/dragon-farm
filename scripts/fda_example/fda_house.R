# Item 2: does fine-tuning teach a house style better than a system prompt?
# Usage, from the package root: Rscript scripts/fda_example/fda_house.R <step>
# step = questions | train | ask. Results go to ~/dragonfarm_runs/fda-example.
suppressMessages(devtools::load_all(".", quiet = TRUE))
options(dragonfarm.runs_dir = path.expand("~/dragonfarm_runs"))
W <- path.expand("~/dragonfarm_runs/fda-example"); dir.create(W, showWarnings = FALSE, recursive = TRUE)
source("scripts/fda_example/fda_questions.R")
say <- function(...) { m <- sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), paste0(...)); cat(m, "\n"); cat(m, "\n", file = file.path(W, "house_log.txt"), append = TRUE) }
step <- commandArgs(trailingOnly = TRUE)[1]
docs <- dragon_documents_load("fda-stats")

TITLES <- c(covariates = "Adjusting for Covariates in Randomized Clinical Trials (FDA, 2023)",
            endpoints = "Multiple Endpoints in Clinical Trials (FDA, 2022)",
            estimands = "E9(R1) Estimands and Sensitivity Analysis (ICH, 2021)",
            software = "Statistical Software Clarifying Statement (FDA, 2015)")
title_of <- function(source) {
  key <- ifelse(grepl("covariate", source), "covariates", ifelse(grepl("endpoints", source), "endpoints",
         ifelse(grepl("e9r1|estimand", source), "estimands", "software")))
  unname(TITLES[key])
}
FORMAT <- paste0('Reply in exactly two lines and nothing else. Line 1: "Answer: " followed by the answer in one sentence, ',
                 'citing excerpts like [1]. Line 2: "Guidance: " followed by the title of the guidance the answer comes from, one of: ',
                 paste(TITLES, collapse = "; "), '. If the documents do not cover the question, write ',
                 '"Answer: The documents do not cover this." and "Guidance: none".')

if (step == "questions") {
  t0 <- Sys.time()
  qa <- dragon_questions(docs)
  dragon_questions_save(qa)
  saveRDS(qa, file.path(W, "house_qa.rds"))
  say(sprintf("questions: %d pairs, %d kept, %.1f min", nrow(qa), sum(qa$keep), as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

if (step == "train") {
  qa <- readRDS(file.path(W, "house_qa.rds"))
  ds <- dragon_questions_dataset(qa, docs)
  d <- ds$data
  d$answer <- ifelse(d$negative, "Answer: The documents do not cover this.\nGuidance: none",
                     paste0("Answer: ", d$answer, "\nGuidance: ", title_of(d$source)))
  hs <- dragon_map(dragon_dataset(d, name = "fda-stats house style"),
                   prompt = "Documentation excerpts:\n{context}\n\nQuestion: {question}", response = "answer")
  t0 <- Sys.time()
  run <- dragon_train(hs, "Qwen/Qwen2.5-3B-Instruct", name = "fda-house-3b",
                      hardware = dragon_hardware(load_in_4bit = TRUE),
                      args = dragon_train_args(batch_size = 1, grad_accum = 16, gradient_checkpointing = TRUE, max_seq_len = 1536),
                      wait = TRUE)
  writeLines(run$dir, file.path(W, "house_run.txt"))
  say(sprintf("train: %s, %d rows, state %s, %.1f min", run$id, nrow(d), dragon_status(run)$state,
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

if (step == "ask") {
  REFUSAL <- "(do(es)?( not|n't)|did not) (cover|mention|contain|provide|include|address)|not (covered|mentioned)|no (information|mention)"
  run <- dragon_run(readLines(file.path(W, "house_run.txt")))
  arms <- list("3B + format prompt" = list(model = run, base = TRUE, system = FORMAT),
               "3B trained, no prompt" = list(model = run, base = FALSE, system = NULL),
               "3B trained + format prompt" = list(model = run, base = FALSE, system = FORMAT))
  qs <- rbind(data.frame(question = FDA_QUESTIONS$question, pattern = FDA_QUESTIONS$pattern, doc = FDA_QUESTIONS$doc, kind = "answerable"),
              data.frame(question = FDA_UNANSWERABLE, pattern = NA_character_, doc = NA_character_, kind = "unanswerable"))
  rows <- list()
  for (lab in names(arms)) {
    a <- arms[[lab]]
    for (i in seq_len(nrow(qs))) {
      t0 <- Sys.time()
      ans <- tryCatch(dragon_ask(docs, qs$question[i], model = a$model, base = a$base, system = a$system)$answer,
                      error = function(e) paste("ERROR:", conditionMessage(e)))
      ans <- trimws(ans %||% "")
      lines <- strsplit(ans, "\n")[[1]]; lines <- lines[nzchar(trimws(lines))]
      fmt <- length(lines) == 2 && grepl("^Answer: ", lines[1]) && grepl("^Guidance: ", lines[2])
      guide <- sub("^.*Guidance:\\s*", "", if (any(grepl("Guidance:", lines))) lines[grep("Guidance:", lines)[1]] else "")
      want <- if (qs$kind[i] == "answerable") TITLES[[qs$doc[i]]] else "none"
      guide_ok <- tolower(trimws(sub("[.]$", "", guide))) == tolower(want)
      right <- if (qs$kind[i] == "answerable") grepl(qs$pattern[i], ans, perl = TRUE) else grepl(REFUSAL, ans, ignore.case = TRUE, perl = TRUE)
      rows[[length(rows) + 1]] <- data.frame(arm = lab, kind = qs$kind[i], question = qs$question[i], format = fmt, guidance = guide_ok,
                                             right = right, seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")), answer = ans)
    }
    r <- do.call(rbind, rows); r <- r[r$arm == lab, ]
    say(sprintf("ask %s: format %d/32, guidance right %d/32, right %d/24, declined %d/8, median %.1fs", lab, sum(r$format), sum(r$guidance),
                sum(r$right[r$kind == "answerable"]), sum(r$right[r$kind == "unanswerable"]), median(r$seconds)))
    dragon_worker_stop()
  }
  saveRDS(do.call(rbind, rows), file.path(W, "house_answers.rds"))
}
