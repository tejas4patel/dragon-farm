# Synthetic data: a teacher writes replies to make fine-tuning data, and a
# judge ranks the student's own samples to make preference pairs. This is
# what turns the stages into a loop: train, sample, judge, train again.

# Any of the ways a model can be named, as function(prompts) -> replies.
as_llm <- function(x, role = c("judge", "teacher", "student"), temperature = 0,
                   max_new_tokens = 400, system = NULL, backend = dragon_backend()) {
  role <- match.arg(role)
  if (is.null(x)) {
    hints <- switch(role,
      judge = c(
        "i" = "Pass {.code judge = dragon_judge_anthropic()} to use the Claude API (needs {.envvar ANTHROPIC_API_KEY}),",
        "i" = "a model id such as {.val Qwen/Qwen2.5-1.5B-Instruct} to judge with a local model,",
        "i" = "an {.pkg ellmer} chat object, or any function from prompts to replies."
      ),
      teacher = c(
        "i" = "Pass {.code teacher = dragon_llm_anthropic()} to use the Claude API (needs {.envvar ANTHROPIC_API_KEY}),",
        "i" = "a model id or a finished run to use a local model, an {.pkg ellmer} chat, or any function from prompts to replies."
      ),
      student = c(
        "i" = "Pass the run whose replies you want to improve, or any model id, ellmer chat, or function from prompts to replies."
      )
    )
    cli::cli_abort(c(paste0("No ", role, " given."), hints))
  }
  if (is.function(x)) return(x)
  if (inherits(x, "Chat")) return(dragon_llm_ellmer(x, system = system))
  if (inherits(x, "dragon_run")) {
    run <- x
    fn <- function(prompts) dragon_generate(run, prompts, system = system, temperature = temperature, max_new_tokens = max_new_tokens, backend = backend)
    attr(fn, "label") <- paste0("run:", run$id)
    return(fn)
  }
  if (is.character(x) && length(x) == 1 && nzchar(x)) {
    model <- x
    fn <- function(prompts) dragon_generate(model, prompts, system = system, temperature = temperature, max_new_tokens = max_new_tokens, backend = backend)
    attr(fn, "label") <- paste0("local:", model)
    return(fn)
  }
  cli::cli_abort("{.arg {role}} must be a function, an ellmer chat, a run, or a model id.")
}

llm_label <- function(fn) attr(fn, "label") %||% "custom"

# Call an LLM function and insist on one reply per prompt.
call_llm <- function(fn, prompts, what = "model") {
  if (!length(prompts)) return(character())
  out <- fn(prompts)
  if (!is.character(out) || length(out) != length(prompts)) {
    cli::cli_abort("The {what} returned {length(out)} repl{?y/ies} for {length(prompts)} prompt{?s}.")
  }
  out
}

usable_reply <- function(x) !is.na(x) & nzchar(trimws(x)) & !startsWith(x, "__error__")

# Prompts from a character vector or a mapped dataset's prompt template.
as_prompt_vector <- function(prompts) {
  if (inherits(prompts, "dragon_dataset")) {
    check_dataset(prompts, mapped = TRUE)
    prompts <- render_template(prompts$mapping$prompt, prompts$data)
  }
  if (!is.character(prompts)) cli::cli_abort("{.arg prompts} must be a character vector or a mapped {.cls dragon_dataset}.")
  prompts <- prompts[!is.na(prompts) & nzchar(trimws(prompts))]
  if (!length(prompts)) cli::cli_abort("No usable prompts.")
  prompts
}

#' Prompts from a run's data files
#'
#' The user turns of a run's training or held-out rows, for feeding
#' [dragon_synthesize_pairs()] or [dragon_judge()]. Works for prompt/response
#' and preference-pair runs alike.
#'
#' @param run A `dragon_run` or run directory.
#' @param split `"eval"` for the held-out rows, `"train"` for the rest.
#' @param n Maximum number of prompts. `Inf` for all.
#' @param seed Seed used when sampling down to `n`.
#' @return A character vector.
#' @export
dragon_prompts <- function(run, split = c("eval", "train"), n = Inf, seed = 42) {
  run <- dragon_run(run)
  split <- match.arg(split)
  cfg <- run_config(run)
  rel <- cfg$data[[split]]
  if (is.null(rel) || !file.exists(run_path(run, rel))) return(character())
  rows <- read_jsonl(run_path(run, rel))
  user_of <- function(msgs) {
    hit <- Filter(function(m) identical(m$role, "user"), msgs)
    if (length(hit)) hit[[length(hit)]]$content else NA_character_
  }
  prompts <- if (identical(cfg$data$format, "pairs")) {
    vapply(rows, function(r) user_of(r$prompt), character(1))
  } else {
    vapply(rows, function(r) user_of(r$messages), character(1))
  }
  prompts <- prompts[!is.na(prompts) & nzchar(prompts)]
  if (is.finite(n) && length(prompts) > n) {
    idx <- local({
      old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
      on.exit(if (!is.null(old)) assign(".Random.seed", old, envir = globalenv()))
      set.seed(seed)
      sort(sample.int(length(prompts), n))
    })
    prompts <- prompts[idx]
  }
  prompts
}

synth_path <- function(runs_dir, name, kind) {
  dir <- file.path(runs_dir, "synth")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  file.path(dir, sprintf("%s-%s-%s.jsonl", format(Sys.time(), "%Y%m%d-%H%M%S"), slugify(name), kind))
}

write_synth <- function(df, file, meta) {
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  rows <- lapply(seq_len(nrow(df)), function(i) as.list(df[i, , drop = FALSE]))
  write_jsonl(rows, file)
  write_json(meta, paste0(tools::file_path_sans_ext(file), ".meta.json"))
  invisible(file)
}

#' Write fine-tuning data with a teacher model
#'
#' Sends each prompt to a stronger model and keeps its replies as the
#' responses to train on. This is the fastest way to get good training data
#' for a small model: a few hundred prompts from your domain, answered the
#' way you want them answered. The result is saved as JSONL and returned as a
#' mapped dataset ready for [dragon_train()].
#'
#' @param prompts A character vector of prompts, or a mapped `dragon_dataset`
#'   whose prompt template is rendered for every row. See [dragon_prompts()]
#'   for prompts from an existing run.
#' @param teacher The model that writes the replies: [dragon_llm_anthropic()],
#'   an `ellmer` chat, a model id or directory, a finished run, or any
#'   function from prompts to replies.
#' @param system System prompt for the teacher. Also stored with every row
#'   so the student trains with the same instruction.
#' @param max_new_tokens Reply length cap for local teachers.
#' @param temperature Sampling temperature for local teachers.
#' @param file Where to write the JSONL. Defaults to a timestamped file under
#'   `synth/` in `runs_dir`.
#' @param runs_dir Parent directory for the default `file`.
#' @param name Label used in the default file name.
#' @return A `dragon_dataset` mapped with prompt and response columns (and
#'   system, when given). The file path is its `source`, so [dragon_code()]
#'   reproduces runs trained on it.
#' @export
#' @examples
#' \dontrun{
#' tickets <- dragon_dataset("tickets.csv") |>
#'   dragon_map(prompt = "{subject}\n\n{body}", response = "reply")
#' persona <- "You are a concise, warm support agent for a smart-home company."
#' teacher <- dragon_llm_anthropic(system = persona)
#' synth <- dragon_synthesize(tickets, teacher, system = persona)
#' run <- dragon_train(synth, "Qwen/Qwen2.5-0.5B-Instruct", wait = TRUE)
#' }
dragon_synthesize <- function(prompts, teacher, system = NULL, max_new_tokens = 512, temperature = 0.7,
                              file = NULL, runs_dir = dragon_runs_dir(), name = "synthetic") {
  prompts <- as_prompt_vector(prompts)
  fn <- as_llm(teacher, role = "teacher", temperature = temperature, max_new_tokens = max_new_tokens, system = system)
  cli::cli_alert_info("Asking {llm_label(fn)} to answer {length(prompts)} prompt{?s}.")
  replies <- call_llm(fn, prompts, "teacher")
  keep <- usable_reply(replies)
  if (!any(keep)) cli::cli_abort("The teacher returned no usable replies.")
  df <- data.frame(prompt = prompts[keep], response = trimws(replies[keep]), stringsAsFactors = FALSE)
  if (!is.null(system)) df$system <- system

  file <- file %||% synth_path(runs_dir, name, "sft")
  meta <- list(kind = "sft", teacher = llm_label(fn), system = system, n_prompts = length(prompts),
               n_kept = nrow(df), created_at = now_iso())
  write_synth(df, file, meta)
  ds <- dragon_dataset(file, name = basename(file))
  ds <- dragon_map(ds, prompt = "prompt", response = "response", system = if (!is.null(system)) "system")
  attr(ds, "synthesis") <- meta
  cli::cli_alert_success("Wrote {nrow(df)} row{?s} to {.path {file}}{if (sum(!keep)) paste0(' (', sum(!keep), ' empty or failed replies dropped)') else ''}.")
  ds
}

#' Build preference pairs from a model's own samples
#'
#' Preference optimization needs, for each prompt, a better and a worse
#' reply. This function makes them without hand labelling, in one of two
#' ways:
#'
#' * With a `judge`: the student answers each prompt `n_samples` times at a
#'   non-zero temperature, the judge scores every sample from 1 to 10, and
#'   the best and worst become the chosen and rejected replies. Prompts whose
#'   samples are too close (`min_gap`) or identical are dropped. This is the
#'   loop behind RLAIF-style training: the model improves on its own outputs
#'   under a judge's preferences.
#' * With a `teacher`: the teacher's reply is chosen and the student's is
#'   rejected. Cheap and effective when the teacher is clearly stronger.
#'
#' The result is saved as JSONL and returned as a dataset mapped with
#' [dragon_map_pairs()], ready for [dragon_prefer()], usually continuing from
#' the student run itself.
#'
#' @inheritParams dragon_synthesize
#' @param student The model whose replies are being improved: normally the
#'   `dragon_run` you will continue from. Also a model id, ellmer chat, or
#'   function.
#' @param judge Scores the student's samples. See [dragon_judge()] for what
#'   is accepted. Required unless `teacher` is given.
#' @param teacher Writes the chosen reply instead of judging. See
#'   [dragon_synthesize()].
#' @param n_samples Samples per prompt in judge mode. At least 2.
#' @param min_gap Minimum score difference between chosen and rejected in
#'   judge mode. Pairs below it are dropped.
#' @param rubric What the judge should value. See [dragon_judge()].
#' @param temperature Sampling temperature for the student. Needs to be
#'   above zero in judge mode, or every sample is the same.
#' @return A `dragon_dataset` mapped as preference pairs. In judge mode the
#'   file also records `chosen_score` and `rejected_score`.
#' @export
#' @examples
#' \dontrun{
#' # Close the loop: sample from the fine-tuned run, let a judge rank, train DPO on the result.
#' pairs <- dragon_synthesize_pairs(dragon_prompts(sft, "train", n = 200), student = sft,
#'                                  judge = dragon_judge_anthropic(model = "claude-sonnet-5"))
#' dpo <- dragon_prefer(pairs, sft, wait = TRUE)
#' dragon_judge(dpo, against = "base", judge = dragon_judge_anthropic())
#' }
dragon_synthesize_pairs <- function(prompts, student, judge = NULL, teacher = NULL, n_samples = 4, min_gap = 2,
                                    rubric = NULL, system = NULL, temperature = 0.8, max_new_tokens = 256,
                                    file = NULL, runs_dir = dragon_runs_dir(), name = "preferences") {
  prompts <- as_prompt_vector(prompts)
  if (is.null(judge) && is.null(teacher)) {
    cli::cli_abort(c(
      "Give a {.arg judge} or a {.arg teacher}.",
      "i" = "A judge ranks the student's own samples; a teacher's reply becomes the chosen one and the student's the rejected one."
    ))
  }
  check_number(n_samples, "n_samples", min = 1, integer = TRUE)
  check_number(min_gap, "min_gap", min = 0)
  student_fn <- as_llm(student, role = "student", temperature = temperature, max_new_tokens = max_new_tokens, system = system)

  if (!is.null(teacher)) {
    teacher_fn <- as_llm(teacher, role = "teacher", temperature = 0.7, max_new_tokens = max(max_new_tokens, 400), system = system)
    cli::cli_alert_info("Teacher {llm_label(teacher_fn)} and student {llm_label(student_fn)} answer {length(prompts)} prompt{?s}.")
    chosen <- trimws(call_llm(teacher_fn, prompts, "teacher"))
    rejected <- trimws(call_llm(student_fn, prompts, "student"))
    keep <- usable_reply(chosen) & usable_reply(rejected) & normalize_text(chosen) != normalize_text(rejected)
    df <- data.frame(prompt = prompts[keep], chosen = chosen[keep], rejected = rejected[keep], stringsAsFactors = FALSE)
    meta <- list(kind = "pairs", mode = "teacher", teacher = llm_label(teacher_fn), student = llm_label(student_fn))
  } else {
    if (n_samples < 2) cli::cli_abort("{.arg n_samples} must be at least 2 so the judge has something to rank.")
    if (!is.function(student) && temperature <= 0) cli::cli_abort("{.arg temperature} must be above 0 so the samples differ.")
    judge_fn <- as_judge(judge)
    rep_prompts <- rep(prompts, each = n_samples)
    cli::cli_alert_info("Sampling {n_samples} replies per prompt from {llm_label(student_fn)} ({length(rep_prompts)} generations).")
    samples <- trimws(call_llm(student_fn, rep_prompts, "student"))
    cli::cli_alert_info("Scoring {length(samples)} samples with {llm_label(judge_fn)}.")
    scored <- judge_scores(rep_prompts, samples, rep(NA_character_, length(rep_prompts)), judge_fn, rubric)
    score <- scored$details$score
    group <- rep(seq_along(prompts), each = n_samples)
    picked <- lapply(seq_along(prompts), function(g) {
      i <- which(group == g & !is.na(score) & usable_reply(samples))
      if (length(i) < 2) return(NULL)
      best <- i[which.max(score[i])]
      worst <- i[which.min(score[i])]
      gap <- score[best] - score[worst]
      if (gap < min_gap || normalize_text(samples[best]) == normalize_text(samples[worst])) return(NULL)
      data.frame(prompt = prompts[g], chosen = samples[best], rejected = samples[worst],
                 chosen_score = score[best], rejected_score = score[worst], stringsAsFactors = FALSE)
    })
    picked <- Filter(Negate(is.null), picked)
    df <- if (length(picked)) do.call(rbind, picked) else
      data.frame(prompt = character(), chosen = character(), rejected = character(),
                 chosen_score = numeric(), rejected_score = numeric(), stringsAsFactors = FALSE)
    meta <- list(kind = "pairs", mode = "judge", judge = llm_label(judge_fn), student = llm_label(student_fn),
                 n_samples = n_samples, min_gap = min_gap, rubric = rubric,
                 unparsed_scores = scored$summary$unparsed)
  }
  if (!nrow(df)) {
    cli::cli_abort(c(
      "No preference pairs survived.",
      "i" = if (is.null(teacher)) "Lower {.arg min_gap}, raise {.arg n_samples} or {.arg temperature}, or check that the judge returns scores." else
        "The teacher and student gave identical or empty replies for every prompt."
    ))
  }
  if (!is.null(system)) df$system <- system
  meta <- c(meta, list(system = system, n_prompts = length(prompts), n_kept = nrow(df), created_at = now_iso()))

  file <- file %||% synth_path(runs_dir, name, "pairs")
  write_synth(df, file, meta)
  ds <- dragon_dataset(file, name = basename(file))
  ds <- dragon_map_pairs(ds, prompt = "prompt", chosen = "chosen", rejected = "rejected",
                         system = if (!is.null(system)) "system")
  attr(ds, "synthesis") <- meta
  cli::cli_alert_success("Kept {nrow(df)} pair{?s} from {length(prompts)} prompt{?s}; written to {.path {file}}.")
  if (is.null(teacher)) {
    cli::cli_text("Mean chosen score {round(mean(df$chosen_score), 2)} vs rejected {round(mean(df$rejected_score), 2)}.")
  }
  ds
}

# Reload pairs that dragon_synthesize_pairs() wrote, e.g. from a pipeline record.
load_synth_pairs <- function(file) {
  ds <- dragon_dataset(file, name = basename(file))
  ds <- dragon_map_pairs(ds, prompt = "prompt", chosen = "chosen", rejected = "rejected",
                         system = if ("system" %in% names(ds$data)) "system")
  meta_path <- paste0(tools::file_path_sans_ext(file), ".meta.json")
  if (file.exists(meta_path)) attr(ds, "synthesis") <- read_json(meta_path)
  ds
}
