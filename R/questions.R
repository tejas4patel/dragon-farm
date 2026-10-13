#' Write questions and answers from a document set
#'
#' Turns documents into training data. For each chunk a model writes a few
#' self-contained questions and answers them from that chunk alone; simple
#' deterministic filters then mark pairs that are not grounded in the chunk,
#' name things the chunk does not, refer to "the passage", or duplicate
#' another question. Nothing is dropped: every pair comes back with `keep`
#' and, when rejected, a `reason`, so you can review them (the Documents tab
#' has a screen for it) before training with [dragon_questions_dataset()].
#'
#' Review them. On the package's own documentation about 60 percent of a
#' 7B model's pairs were usable, 33 percent of a 3B's, 20 percent of a
#' 1.5B's, and a fifth of what passed the filters was still wrong or trivial.
#' Quoted material and changelog-like sources are skipped by default because
#' they produced the worst pairs.
#'
#' @param docs A `dragon_documents` object or its directory.
#' @param generator What writes the pairs. `NULL` uses the local model
#'   recommended for this machine (see [dragon_check()]); a model id uses
#'   that local model; a teacher such as [dragon_llm_anthropic()], an
#'   `ellmer` chat, a run, or any function from prompts to replies is called
#'   from R instead. Local generation runs as a background Python process.
#' @param n_per_chunk Questions asked for per chunk.
#' @param include_quotes,include_code,include_changelog Which chunks to use.
#'   Block quotes are skipped by default (a quoted example reply is not your
#'   policy), code blocks are included, changelog-like sources are skipped.
#' @param load_in_4bit For a local generator: `"auto"`, `TRUE`, or `FALSE`;
#'   see [dragon_backend_local()].
#' @param batch_size,max_new_tokens Local generation settings.
#' @param wait Block until done. With `FALSE`, a local generation returns a
#'   job to poll with [dragon_questions_progress()] and finish with
#'   [dragon_questions_wait()]; a teacher always runs to completion.
#' @return A `dragon_questions` data frame: `id`, `chunk_id`, `source`,
#'   `section`, `question`, `answer`, `keep`, `reason`, `decided_by`, with
#'   the file it was saved to in `attr(, "path")` and the set in
#'   `attr(, "documents")`. Edit `keep` and [dragon_questions_save()] it.
#' @export
#' @examples
#' if (interactive()) {
#' docs <- dragon_documents("policies/")
#' qa <- dragon_questions(docs)                      # local model, background, waits
#' qa                                                # how many kept, and why not
#' qa$keep[qa$id == "p0007"] <- TRUE                 # rescue one after reading it
#' dragon_questions_save(qa)
#' ds <- dragon_questions_dataset(qa, docs)          # excerpts retrieved into every prompt
#' run <- dragon_train(ds, "Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)
#' }
dragon_questions <- function(docs, generator = NULL, n_per_chunk = 3, include_quotes = FALSE, include_code = TRUE,
                             include_changelog = FALSE, load_in_4bit = "auto", batch_size = 4,
                             max_new_tokens = 420, wait = TRUE) {
  docs <- as_documents(docs)
  check_number(n_per_chunk, "n_per_chunk", min = 1, max = 10, integer = TRUE)
  out_dir <- file.path(docs$dir, "questions")
  dir.create(out_dir, showWarnings = FALSE)
  out <- file.path(out_dir, paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), ".jsonl"))
  sel <- c("--per-chunk", as.character(as.integer(n_per_chunk)),
           if (isTRUE(include_quotes)) "--include-quotes", if (!isTRUE(include_code)) "--skip-code",
           if (isTRUE(include_changelog)) "--include-changelog")

  local_model <- is.null(generator) || (is.character(generator) && length(generator) == 1L)
  if (!local_model) {
    # A teacher called from R: prompts from Python, replies from the teacher,
    # parsing and filtering back in Python so both paths judge pairs alike.
    fn <- as_llm(generator, role = "teacher", max_new_tokens = 200L * as.integer(n_per_chunk) + 100L)
    res <- run_python("dragonfarm.questions", c("prompts", "--dir", docs$dir, sel))
    if (res$status != 0) python_failure_message(res, "Preparing question prompts")
    prompts <- jsonlite::fromJSON(res$stdout, simplifyVector = FALSE)
    if (!length(prompts)) cli::cli_abort("No chunks to write questions from (all were quotes, code, or changelog entries that are skipped by default).")
    cli::cli_alert_info("Asking {llm_label(fn)} for questions on {length(prompts)} chunk{?s}.")
    replies <- call_llm(fn, vapply(prompts, `[[`, "", "prompt"), what = "teacher")
    raw <- tempfile(fileext = ".json")
    jsonlite::write_json(lapply(seq_along(prompts), function(i) list(chunk_id = prompts[[i]]$chunk_id, output = replies[i])),
                         raw, auto_unbox = TRUE)
    res <- run_python("dragonfarm.questions", c("filter", "--dir", docs$dir, "--raw", raw, "--out", out, "--generator", llm_label(fn)))
    if (res$status != 0) python_failure_message(res, "Filtering questions")
    qa <- dragon_questions_load(out)
    report_questions(qa)
    return(qa)
  }

  model <- generator %||% default_answer_model()
  if (worker_alive()) {
    cli::cli_alert_info("Stopping the local inference worker so the generator has the whole GPU.")
    dragon_worker_stop()
  }
  py <- dragon_python(quiet = TRUE)
  args <- c("-m", "dragonfarm.questions", "generate", "--dir", docs$dir, "--out", out, "--model", model,
            "--load-in-4bit", tolower(as.character(load_in_4bit)), "--batch-size", as.character(as.integer(batch_size)),
            "--max-new-tokens", as.character(as.integer(max_new_tokens)), sel)
  log <- paste0(out, ".log")
  p <- processx::process$new(py, args, stdout = log, stderr = "2>&1", env = python_env(), cleanup = TRUE,
                             windows_hide_window = TRUE)
  job <- structure(list(process = p, out = out, progress = paste0(out, ".progress.json"), log = log,
                        documents = docs$dir, model = model, started = Sys.time()), class = "dragon_questions_job")
  cli::cli_alert_info("Writing questions with {.val {model}} in the background. Progress: {.path {basename(out)}}")
  if (!wait) return(job)
  dragon_questions_wait(job)
}

#' @rdname dragon_questions
#' @param job A job from `dragon_questions(wait = FALSE)`.
#' @export
dragon_questions_progress <- function(job) {
  p <- if (file.exists(job$progress)) tryCatch(read_json(job$progress), error = function(e) NULL)
  alive <- tryCatch(job$process$is_alive(), error = function(e) FALSE)
  if (is.null(p)) p <- list(state = if (alive) "loading" else "failed", done = 0L, total = NA_integer_, pairs = 0L, kept = 0L)
  if (!alive && !identical(p$state, "done")) p$state <- "failed"
  p$alive <- alive
  p
}

#' @rdname dragon_questions
#' @export
dragon_questions_wait <- function(job) {
  id <- cli::cli_progress_bar("Writing questions", total = NA, clear = TRUE)
  repeat {
    p <- dragon_questions_progress(job)
    if (!is.na(p$total) && p$total > 0) {
      cli::cli_progress_update(id = id, set = p$done, total = p$total,
                               status = sprintf("%d of %d chunks, %d pairs, %d kept", p$done, p$total, p$pairs, p$kept))
    }
    if (identical(p$state, "done")) break
    if (identical(p$state, "failed")) {
      cli::cli_progress_done(id = id)
      cli::cli_abort(c("Question generation failed.", "i" = "Last lines of the log:", " " = paste(tail_lines(job$log, 12), collapse = "\n")))
    }
    Sys.sleep(1)
  }
  cli::cli_progress_done(id = id)
  qa <- dragon_questions_load(job$out)
  report_questions(qa)
  qa
}

report_questions <- function(qa) {
  n <- nrow(qa); k <- sum(qa$keep)
  cli::cli_alert_success("{n} question{?s} written, {k} kept by the filters ({if (n) round(100 * k / n) else 0}%). Review them before training.")
  if (n > k) {
    why <- sort(table(sub(" \\(.*", "", qa$reason[!qa$keep])), decreasing = TRUE)
    cli::cli_text("Rejected: {paste(sprintf('%s (%d)', names(why), why), collapse = ', ')}.")
  }
  invisible(qa)
}

#' Load, save, and list question sets
#'
#' @param path A questions file (`<set>/questions/<stamp>.jsonl`), or a
#'   `dragon_questions` object for `dragon_questions_save()`.
#' @param qa A `dragon_questions` data frame whose `keep` column you edited.
#' @param docs A `dragon_documents` object or directory.
#' @return `dragon_questions_load()` and `dragon_questions_save()` return the
#'   `dragon_questions` data frame; `dragon_questions_list()` a data frame of
#'   the set's question files with counts.
#' @export
dragon_questions_load <- function(path) {
  check_string(path, "path")
  if (!file.exists(path)) cli::cli_abort("{.path {path}} does not exist.")
  recs <- read_jsonl(path)
  df <- data.frame(
    id = vapply(recs, function(r) r$id, ""), chunk_id = vapply(recs, function(r) r$chunk_id, ""),
    source = vapply(recs, function(r) r$source, ""), section = vapply(recs, function(r) r$section %||% "", ""),
    question = vapply(recs, function(r) r$question, ""), answer = vapply(recs, function(r) r$answer, ""),
    keep = vapply(recs, function(r) isTRUE(r$keep), NA), reason = vapply(recs, function(r) r$reason %||% NA_character_, ""),
    decided_by = vapply(recs, function(r) r$decided_by %||% "filter", ""), stringsAsFactors = FALSE
  )
  meta_path <- paste0(path, ".meta.json")
  meta <- if (file.exists(meta_path)) tryCatch(read_json(meta_path), error = function(e) NULL)
  structure(df, path = normalizePath(path, winslash = "/"), documents = dirname(dirname(normalizePath(path, winslash = "/"))),
            meta = meta, class = c("dragon_questions", "data.frame"))
}

#' @rdname dragon_questions_load
#' @export
dragon_questions_save <- function(qa, path = attr(qa, "path")) {
  if (!inherits(qa, "dragon_questions")) cli::cli_abort("{.arg qa} must come from {.fn dragon_questions}.")
  check_string(path, "path")
  recs <- lapply(seq_len(nrow(qa)), function(i) list(
    id = qa$id[i], chunk_id = qa$chunk_id[i], source = qa$source[i], section = qa$section[i],
    question = qa$question[i], answer = qa$answer[i], keep = isTRUE(qa$keep[i]),
    reason = if (is.na(qa$reason[i])) NULL else qa$reason[i],
    decided_by = if (isTRUE(qa$keep[i]) != is.na(qa$reason[i])) "person" else qa$decided_by[i]
  ))
  write_jsonl(recs, path)
  invisible(dragon_questions_load(path))
}

#' @rdname dragon_questions_load
#' @export
dragon_questions_list <- function(docs) {
  docs <- as_documents(docs)
  files <- sort(list.files(file.path(docs$dir, "questions"), pattern = "^[0-9-]+\\.jsonl$", full.names = TRUE), decreasing = TRUE)
  rows <- lapply(files, function(f) {
    meta_path <- paste0(f, ".meta.json")
    m <- if (file.exists(meta_path)) tryCatch(read_json(meta_path), error = function(e) NULL)
    n <- length(readLines(f, warn = FALSE))
    data.frame(file = normalizePath(f, winslash = "/"), stamp = sub("\\.jsonl$", "", basename(f)),
               generator = m$generator %||% NA_character_, pairs = n, kept = as.integer(m$n_kept %||% NA),
               finished = !is.null(m), stringsAsFactors = FALSE)
  })
  if (!length(rows)) return(data.frame(file = character(), stamp = character(), generator = character(),
                                       pairs = integer(), kept = integer(), finished = logical(), stringsAsFactors = FALSE))
  do.call(rbind, rows)
}

#' Training data from reviewed questions
#'
#' Builds the dataset the fine-tune trains on: for every kept question, the
#' `k` most relevant excerpts are retrieved from the documents (by the
#' question, not the chunk it was written from, so training matches what
#' happens at answer time) and placed in the prompt ahead of it; the answer
#' is the response. This is the setup that beat a plain fine-tune in the
#' prototypes: the model learns to use excerpts, and the documents stay the
#' source of truth and can change later without retraining.
#'
#' @param qa A `dragon_questions` data frame (only rows with `keep = TRUE` are used).
#' @param docs The document set; defaults to the one the questions came from.
#' @param k Excerpts per prompt.
#' @return A mapped `dragon_dataset` ready for [dragon_train()].
#' @export
dragon_questions_dataset <- function(qa, docs = NULL, k = 4) {
  if (!inherits(qa, "dragon_questions")) cli::cli_abort("{.arg qa} must come from {.fn dragon_questions}.")
  docs <- as_documents(docs %||% attr(qa, "documents"))
  kept <- qa[qa$keep, , drop = FALSE]
  if (!nrow(kept)) cli::cli_abort("No kept questions. Review the set and keep at least a few.")
  hits <- dragon_retrieve(docs, kept$question, k = k)
  if (is.null(hits$query)) hits$query <- kept$question[1]   # one question: dragon_retrieve drops the column
  context <- vapply(seq_len(nrow(kept)), function(i) {
    h <- hits[hits$query == kept$question[i], , drop = FALSE]
    paste(sprintf("[%d] %s%s\n%s", h$n, h$source, ifelse(nzchar(h$section), paste0(" › ", h$section), ""), h$text), collapse = "\n\n")
  }, character(1))
  df <- data.frame(question = kept$question, context = context, answer = kept$answer, source = kept$source,
                   stringsAsFactors = FALSE)
  ds <- dragon_dataset(df, name = paste0(docs$name, " questions"))
  dragon_map(ds, prompt = "Documentation excerpts:\n{context}\n\nQuestion: {question}", response = "answer")
}

#' @export
print.dragon_questions <- function(x, ...) {
  n <- nrow(x); k <- sum(x$keep)
  m <- attr(x, "meta")
  cli::cli_h3("{n} question{?s} from {basename(attr(x, 'documents') %||% 'documents')}{if (!is.null(m$generator)) paste0(', written by ', m$generator) else ''}")
  cli::cli_text("{k} kept ({if (n) round(100 * k / n) else 0}%), {n - k} rejected. Edit {.code $keep} and {.fn dragon_questions_save}; then {.fn dragon_questions_dataset}.")
  if (n > k) {
    why <- sort(table(sub(" \\(.*", "", x$reason[!x$keep])), decreasing = TRUE)
    cli::cli_text("Rejected: {paste(sprintf('%s (%d)', names(why), why), collapse = ', ')}.")
  }
  show <- utils::head(x[x$keep, c("source", "question", "answer")], 5)
  if (nrow(show)) {
    cli::cli_text("")
    for (i in seq_len(nrow(show))) cli::cli_text("{.strong Q:} {show$question[i]}\n   {.strong A:} {show$answer[i]}")
    if (k > 5) cli::cli_text("... and {k - 5} more.")
  }
  invisible(x)
}
