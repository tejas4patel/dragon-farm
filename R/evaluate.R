#' Evaluate a finished run
#'
#' Training already evaluates on the held-out rows and writes the result into
#' the run directory. This function reads that result, or recomputes it with
#' the saved adapter when `recompute = TRUE` or nothing was saved.
#'
#' @param run A `dragon_run` or run directory.
#' @param n_samples Number of held-out prompts to generate replies for.
#' @param recompute Reload the model and evaluate again.
#' @return A list with `eval_loss`, `perplexity`, `eval_tokens`, and a
#'   `samples` data frame with columns `prompt`, `reference`, `generated`.
#'   Preference runs report `pref_accuracy` (how often the model scores the
#'   chosen reply above the rejected one), `reward_margin`, and `eval_pairs`
#'   instead of perplexity, and their samples also carry `rejected`.
#' @export
dragon_evaluate <- function(run, n_samples = 10, recompute = FALSE) {
  run <- dragon_run(run)
  eval_path <- run_path(run, "eval.json")
  samples_path <- run_path(run, "samples.json")
  if (recompute || !file.exists(eval_path)) {
    if (!file.exists(run_path(run, "adapter", "adapter_config.json"))) {
      cli::cli_abort("Run {.strong {run$id}} has no saved adapter to evaluate.")
    }
    res <- run_python("dragonfarm.evaluate", c("--run-dir", run$dir, "--n-samples", n_samples))
    if (res$status != 0) python_failure_message(res, "Evaluation")
  }
  metrics <- if (file.exists(eval_path)) read_json(eval_path) else list()
  samples <- if (file.exists(samples_path)) read_json(samples_path) else list()
  samples_df <- if (length(samples)) records_to_df(samples) else
    data.frame(prompt = character(), reference = character(), generated = character(), stringsAsFactors = FALSE)
  structure(
    list(
      eval_loss = metrics$eval_loss, perplexity = metrics$perplexity,
      eval_tokens = metrics$eval_tokens,
      pref_accuracy = metrics$pref_accuracy, reward_margin = metrics$reward_margin,
      eval_pairs = metrics$eval_pairs, method = metrics$method,
      samples = samples_df
    ),
    class = "dragon_eval"
  )
}

#' @export
print.dragon_eval <- function(x, ...) {
  if (!is.null(x$pref_accuracy)) {
    cli::cli_text("{toupper(x$method %||% 'preference')} on {x$eval_pairs} held-out pair{?s}: accuracy {.strong {round(100 * x$pref_accuracy)}%} \u00b7 reward margin {.strong {round(x$reward_margin, 3)}} \u00b7 loss {round(x$eval_loss, 4)}")
  } else if (is.null(x$eval_loss)) {
    cli::cli_text("No held-out rows were evaluated for this run.")
  } else {
    cli::cli_text("Eval loss {.strong {round(x$eval_loss, 4)}} \u00b7 perplexity {.strong {round(x$perplexity, 2)}} over {x$eval_tokens} tokens")
  }
  n <- nrow(x$samples)
  if (n) {
    cli::cli_text("{n} sample generation{?s}. First one:")
    cli::cli_h3("Prompt")
    cli::cli_verbatim(x$samples$prompt[1])
    cli::cli_h3("Generated")
    cli::cli_verbatim(x$samples$generated[1])
    cli::cli_h3("Reference")
    cli::cli_verbatim(x$samples$reference[1])
  }
  invisible(x)
}
