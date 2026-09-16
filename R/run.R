#' Directory where runs are stored
#'
#' Defaults to `dragonfarm_runs` under the working directory. Override with
#' `options(dragonfarm.runs_dir = ...)` or the `DRAGONFARM_RUNS_DIR`
#' environment variable.
#'
#' @return A path.
#' @export
dragon_runs_dir <- function() {
  getOption("dragonfarm.runs_dir", Sys.getenv("DRAGONFARM_RUNS_DIR", unset = "dragonfarm_runs"))
}

new_run <- function(dir, process = NULL) {
  structure(
    list(dir = normalizePath(dir, winslash = "/", mustWork = FALSE), id = basename(dir), process = process),
    class = "dragon_run"
  )
}

#' Reopen an existing run
#'
#' Runs live entirely on disk, so any run can be picked up from a new R
#' session by its directory.
#'
#' @param dir Path to a run directory (one containing `config.json`).
#' @return A `dragon_run` object.
#' @export
dragon_run <- function(dir) {
  if (inherits(dir, "dragon_run")) return(dir)
  check_string(dir, "dir")
  if (!file.exists(file.path(dir, "config.json"))) {
    cli::cli_abort("{.path {dir}} is not a run directory (no config.json).")
  }
  new_run(dir)
}

run_path <- function(run, ...) file.path(run$dir, ...)

run_config <- function(run) read_json(run_path(run, "config.json"))

check_run <- function(run) {
  if (!inherits(run, "dragon_run")) cli::cli_abort("{.arg run} must be a {.cls dragon_run}. Use {.fn dragon_run} to reopen one by path.")
  invisible(run)
}

make_run_id <- function(name) {
  paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), "-", slugify(name))
}

#' List runs
#'
#' @param runs_dir Directory holding run directories.
#' @return A data frame with one row per run, newest first.
#' @export
dragon_runs <- function(runs_dir = dragon_runs_dir()) {
  empty <- data.frame(
    id = character(), dir = character(), state = character(), stage = character(), method = character(),
    model = character(), created_at = character(), eval_loss = numeric(), stringsAsFactors = FALSE
  )
  if (!dir.exists(runs_dir)) return(empty)
  dirs <- list.dirs(runs_dir, recursive = FALSE, full.names = TRUE)
  dirs <- dirs[file.exists(file.path(dirs, "config.json"))]
  if (!length(dirs)) return(empty)
  rows <- lapply(dirs, function(d) {
    cfg <- tryCatch(read_json(file.path(d, "config.json")), error = function(e) NULL)
    st <- tryCatch(read_json(file.path(d, "status.json")), error = function(e) list(state = "unknown"))
    data.frame(
      id = basename(d), dir = normalizePath(d, winslash = "/"),
      state = st$state %||% "unknown",
      stage = cfg$stage %||% "sft",
      method = cfg$prefer$method %||% (if (identical(cfg$stage, "reinforce")) "grpo" else NA_character_),
      model = cfg$model$id %||% NA_character_,
      created_at = cfg$created_at %||% NA_character_,
      eval_loss = as.numeric(st$eval_loss %||% NA_real_),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out[order(out$created_at, decreasing = TRUE), , drop = FALSE]
}

#' @export
print.dragon_run <- function(x, ...) {
  st <- tryCatch(dragon_status(x), error = function(e) list(state = "unknown"))
  cfg <- tryCatch(run_config(x), error = function(e) NULL)
  cli::cli_text("{.cls dragon_run} {.strong {x$id}}")
  cli::cli_text("Directory: {.path {x$dir}}")
  if (!is.null(cfg)) {
    unit <- switch(cfg$data$format %||% "messages", pairs = "pairs", prompts = "prompts", "training rows")
    cli::cli_text("Model: {.val {cfg$model$id}} \u00b7 LoRA r={cfg$lora$r} \u00b7 {cfg$data$n_train} {unit}")
    if (identical(cfg$stage, "prefer")) {
      cli::cli_text("Stage: preference optimization ({toupper(cfg$prefer$method)}, beta {cfg$prefer$beta}){if (!is.null(cfg$model$base_run)) paste0(' \u00b7 continues ', cfg$model$base_run) else ''}")
    } else if (identical(cfg$stage, "reinforce")) {
      cli::cli_text("Stage: reinforcement learning (GRPO, {length(cfg$reinforce$rewards)} reward{?s}, group {cfg$reinforce$group_size}, beta {cfg$reinforce$beta}){if (!is.null(cfg$model$base_run)) paste0(' \u00b7 continues ', cfg$model$base_run) else ''}")
    } else if (!is.null(cfg$model$base_run)) {
      cli::cli_text("Stage: fine-tuning \u00b7 continues {cfg$model$base_run}")
    }
  }
  cli::cli_text("State: {.strong {st$state}}{if (!is.null(st$device)) paste0(' on ', st$device) else ''}")
  pr <- tryCatch(dragon_progress(x), error = function(e) data.frame())
  if (nrow(pr) && "loss" %in% names(pr)) {
    last <- pr[max(which(!is.na(pr$loss))), ]
    cli::cli_text("Progress: step {last$step}{if (!is.null(st$total_steps)) paste0('/', st$total_steps) else ''} \u00b7 loss {round(last$loss, 3)}")
  }
  if (!is.null(st$reward_mean)) {
    cli::cli_text("Held-out reward: {round(st$reward_mean, 3)}")
  } else if (!is.null(st$pref_accuracy)) {
    cli::cli_text("Preference accuracy: {round(100 * st$pref_accuracy)}% \u00b7 reward margin {round(st$reward_margin, 3)} \u00b7 loss {round(st$eval_loss, 3)}")
  } else if (!is.null(st$eval_loss)) {
    cli::cli_text("Eval loss: {round(st$eval_loss, 3)} \u00b7 perplexity {round(st$perplexity, 2)}")
  }
  if (!is.null(st$error)) cli::cli_text("{.strong Error:} {st$error}")
  invisible(x)
}
